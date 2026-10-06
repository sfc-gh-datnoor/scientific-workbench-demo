#!/usr/bin/env bash
# =============================================================================
# deploy.sh — End-to-End Deployment for Snowflake Scientific Workbench
# =============================================================================
# DISCLAIMER: This application is not part of the Snowflake Service and is
# governed by the terms in LICENSE, unless expressly agreed to in writing. You
# use this application at your own risk, and Snowflake has no obligation to
# support your use of this application.
# =============================================================================
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Options:
#   --skip-prereqs      Skip step 0 (use if EAI/secret already exist)
#   --skip-data         Skip reference data loading (saves ~45 min)
#   --skip-app          Skip Next.js app deployment
#   --skip-tests        Skip post-deploy verification
#   --backend-only      Deploy NVIDIA procedures, router agents/skills, and app only
#   --agents-app-only   Resume at router agents/skills, then deploy the app
#   --app-only          Deploy only the App Runtime service
#   --mirror-nims       Mirror NIM container images from nvcr.io (requires --ngc-key + Docker)
#   --nvidia-key KEY    NVIDIA API key (or set NVIDIA_API_KEY env var)
#   --ngc-key KEY       NGC API key for SPCS NIM containers (or set NGC_API_KEY env var)
#   --connection NAME   Snowflake CLI connection name (auto-detected if omitted)
#   --config PATH       Path to workbench.config.yaml (default: workbench.config.yaml)
#   --dry-run           Print what would be executed without running
#   -h, --help          Show this help
#
# Prerequisites:
#   - Snowflake CLI (snow) installed and authenticated
#   - ACCOUNTADMIN access for initial setup
#   - Node.js >= 20 (for app build)
#   - NVIDIA API key from build.nvidia.com
# =============================================================================

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONNECTION=""
CONFIG_FILE=""
NVIDIA_KEY="${NVIDIA_API_KEY:-}"
NGC_KEY="${NGC_API_KEY:-}"
SKIP_PREREQS=false
SKIP_DATA=false
SKIP_APP=false
SKIP_TESTS=false
MIRROR_NIMS=false
DRY_RUN=false
BACKEND_ONLY=false
AGENTS_APP_ONLY=false
APP_ONLY=false

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Helpers ---
log()   { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()    { echo -e "${GREEN}  ✓${NC} $*"; }
warn()  { echo -e "${YELLOW}  ⚠${NC} $*"; }
err()   { echo -e "${RED}  ✗${NC} $*" >&2; }
fatal() { err "$@"; exit 1; }

usage() {
  sed -n '2,/^# ====/p' "$0" | grep '^#' | sed 's/^# \?//'
  exit 0
}

# Execute a SQL file using --query to completely bypass snow CLI template rendering.
# Both --filename and --stdin trigger Go template parsing which breaks on & { } in SQL.
# We read the file content, strip SQL comments (which contain the problematic chars),
# and execute via --query which does NOT template-render.
#
# Scripts may switch roles inline with top-level `USE ROLE X;`. Sessions from a
# role-restricted PAT reject USE ROLE ("Current session is restricted"), so each
# file is split at those lines and every segment runs as its own `snow sql
# --role X` call. The latest USE DATABASE/SCHEMA/WAREHOUSE is carried into each
# later segment. USE ROLE text inside $$ bodies is left alone.
split_sql_by_role() {
  python3 - "$1" "$2" "$3" <<'PY'
import os, re, sys
src, default_role, outdir = sys.argv[1:4]
use_role = re.compile(r'^\s*USE\s+ROLE\s+"?([A-Za-z0-9_$]+)"?\s*;\s*(--.*)?$', re.I)
use_ctx = re.compile(r'^\s*USE\s+(DATABASE|SCHEMA|WAREHOUSE)\s+[^;]+;', re.I)
segments, role, buf, ctx, in_body = [], default_role.upper(), [], {}, False
for line in open(src, encoding='utf-8').read().split('\n'):
    if not in_body:
        m = use_role.match(line)
        if m:
            segments.append((role, buf))
            role = m.group(1).upper()
            buf = [ctx[k] for k in ('DATABASE', 'SCHEMA', 'WAREHOUSE') if k in ctx]
            continue
        c = use_ctx.match(line)
        if c:
            ctx[c.group(1).upper()] = c.group(0).strip()
    buf.append(line)
    if line.count('$$') % 2 and (in_body or not line.lstrip().startswith('--')):
        in_body = not in_body
segments.append((role, buf))

def has_sql(lines):
    text = re.sub(r'/\*.*?\*/', '', '\n'.join(lines), flags=re.S)
    return any(l.strip() and not l.strip().startswith('--') and not use_ctx.match(l)
               for l in text.split('\n'))

n = 0
for seg_role, lines in segments:
    if not has_sql(lines):
        continue
    path = os.path.join(outdir, 'seg_%03d.sql' % n)
    open(path, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
    print('%s\t%s' % (seg_role, path))
    n += 1
PY
}

run_sql() {
  local file="$1"
  local role="${2:-SYSADMIN}"
  local warehouse="${3:-}"
  local desc="${4:-$file}"

  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would execute: $desc (role=$role, warehouse=${warehouse:-<none>})"
    return 0
  fi

  log "Executing: $desc"

  local segdir manifest seg_role seg_file rc=0
  segdir=$(mktemp -d "${TMPDIR:-/tmp}/deploy_seg.XXXXXX")
  if ! manifest=$(split_sql_by_role "$file" "$role" "$segdir"); then
    rm -rf "$segdir"
    err "Failed: $desc (could not split $file by role)"
    return 1
  fi
  while IFS=$'\t' read -r seg_role seg_file; do
    [[ -z "$seg_file" ]] && continue
    run_sql_segment "$seg_file" "$seg_role" "$warehouse" "$desc" "$file" || { rc=1; break; }
  done <<< "$manifest"
  rm -rf "$segdir"
  [[ $rc -eq 0 ]] && ok "$desc"
  return $rc
}

# Run one single-role SQL file. $5 is the original file, for error messages.
run_sql_segment() {
  local file="$1"
  local role="$2"
  local warehouse="$3"
  local desc="$4"
  local source_file="${5:-$1}"

  # Use --filename mode and escape &X to prevent CLI template rendering.
  # Procedure bodies are already dollar-quoted and must not be wrapped again.
  local tmpfile
  tmpfile=$(mktemp "${TMPDIR:-/tmp}/deploy_sql.XXXXXX")
  sed 's/&\([A-Za-z]\)/\&\&\1/g' "$file" > "$tmpfile"

  local -a cmd_args=(
    snow sql
    --connection "$CONNECTION"
    --role "$role"
    --filename "$tmpfile"
  )

  # Only pass --warehouse if specified (some early steps don't have one yet)
  if [[ -n "$warehouse" ]]; then
    cmd_args+=(--warehouse "$warehouse")
  fi

  # Bounded retry on TRANSIENT CONNECTION failures only. Real SQL errors are never
  # retried, so a genuine defect still fails fast. Added because a single flaky
  # connection across ~40 sequential calls previously killed an entire run, and
  # because OAuth/PAT expiry mid-deployment is common on this account.
  local output rc attempt=1 max_attempts=5
  while :; do
    set +e
    output=$("${cmd_args[@]}" 2>&1)
    rc=$?
    set -e
    if [[ $rc -ne 0 && $attempt -lt $max_attempts ]] && printf '%s' "$output" \
       | grep -qE 'Invalid connection configuration|250001|394400|Programmatic access token is invalid|OAuth access token expired|Failed to connect to DB'; then
      warn "$desc: transient connection failure, retry $attempt/$max_attempts in $((attempt * 5))s"
      sleep $((attempt * 5))
      attempt=$((attempt + 1))
      continue
    fi
    break
  done
  rm -f "$tmpfile"

  if [[ $rc -ne 0 ]]; then
    err "Failed: $desc"
    err "  File: $source_file"
    err "  Role: $role"
    while IFS= read -r line; do
      err "  $line"
    done <<< "$output"
    err "  Run manually with: snow sql --connection $CONNECTION --role $role --filename '$source_file'"
    return 1
  fi
}

# Execute inline SQL (single statement)
run_sql_inline() {
  local sql="$1"
  local role="${2:-SYSADMIN}"
  local warehouse="${3:-}"
  local desc="${4:-inline SQL}"

  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would execute: $desc"
    return 0
  fi

  local -a cmd_args=(
    snow sql
    --connection "$CONNECTION"
    --role "$role"
    --query "$sql"
  )

  if [[ -n "$warehouse" ]]; then
    cmd_args+=(--warehouse "$warehouse")
  fi

  local output rc
  set +e
  output=$("${cmd_args[@]}" 2>&1)
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    err "Failed: $desc"
    echo "$output" | tail -3 | while IFS= read -r line; do
      err "  $line"
    done
    return 1
  fi
  ok "$desc"
}

# Auto-detect the best Snowflake CLI connection
detect_connection() {
  # If user specified one, use it
  if [[ -n "$CONNECTION" ]]; then
    return
  fi

  # Try the default connection first
  if snow connection test --connection default > /dev/null 2>&1; then
    CONNECTION="default"
    return
  fi

  # Look for a connection that works (try each one)
  local conn_list
  conn_list=$(snow connection list --format json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for row in data:
        name = row.get('connection_name', '')
        if name:
            print(name)
except: pass
" 2>/dev/null || true)

  if [[ -z "$conn_list" ]]; then
    fatal "No Snowflake CLI connections found. Run: snow connection add"
  fi

  # Try each connection
  while IFS= read -r conn; do
    if snow connection test --connection "$conn" > /dev/null 2>&1; then
      CONNECTION="$conn"
      return
    fi
  done <<< "$conn_list"

  # If none worked, show the list and fail
  fatal "No working Snowflake CLI connection found. Available: $(echo "$conn_list" | tr '\n' ', '). Run: snow connection test --connection <name>"
}

# --- Parse Arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-prereqs) SKIP_PREREQS=true ;;
    --skip-data)    SKIP_DATA=true ;;
    --skip-app)     SKIP_APP=true ;;
    --skip-tests)   SKIP_TESTS=true ;;
    --backend-only) BACKEND_ONLY=true ;;
    --agents-app-only) AGENTS_APP_ONLY=true; BACKEND_ONLY=true; SKIP_PREREQS=true; SKIP_DATA=true ;;
    --app-only) APP_ONLY=true; AGENTS_APP_ONLY=true; BACKEND_ONLY=true; SKIP_PREREQS=true; SKIP_DATA=true ;;
    --mirror-nims)  MIRROR_NIMS=true ;;
    --nvidia-key)   NVIDIA_KEY="$2"; shift ;;
    --ngc-key)      NGC_KEY="$2"; shift ;;
    --connection)   CONNECTION="$2"; shift ;;
    --config)       CONFIG_FILE="$2"; shift ;;
    --dry-run)      DRY_RUN=true ;;
    -h|--help)      usage ;;
    *) fatal "Unknown option: $1" ;;
  esac
  shift
done

# --- Pre-flight Checks ---
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Snowflake Scientific Workbench — Deployment Script      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# --- Load Config File ---
# Config file provides defaults; CLI flags override.
if [[ -z "$CONFIG_FILE" ]]; then
  for candidate in "$SCRIPT_DIR/workbench.config.yaml" "workbench.config.yaml"; do
    [[ -f "$candidate" ]] && CONFIG_FILE="$candidate" && break
  done
fi

if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
  log "Loading config from: $CONFIG_FILE"
  # Simple YAML parser — extract key:value pairs (no yq dependency)
  cfg_get() {
    local parent="${1%%.*}" child="${1#*.}"
    if [[ "$parent" == "$child" ]]; then
      grep -E "^${parent}:" "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/^[^:]*:\s*//' | sed 's/\s*#.*//' | tr -d '"' | tr -d "'" | xargs
    else
      local pline
      pline=$(grep -n "^${parent}:" "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d: -f1)
      [[ -z "$pline" ]] && return
      tail -n +"$((pline + 1))" "$CONFIG_FILE" | grep -E "^\s+${child}:" | head -1 | sed 's/^[^:]*:\s*//' | sed 's/\s*#.*//' | tr -d '"' | tr -d "'" | xargs
    fi
  }
  # Apply config values as defaults (CLI flags take precedence)
  [[ -z "$CONNECTION" ]] && CONNECTION=$(cfg_get snowflake.connection)
  [[ -z "$NVIDIA_KEY" ]] && NVIDIA_KEY=$(cfg_get secrets.nvidia_api_key)
  [[ -z "$NGC_KEY" ]]    && NGC_KEY=$(cfg_get secrets.ngc_api_key)
else
  if [[ -n "$CONFIG_FILE" ]]; then
    warn "Config file not found: $CONFIG_FILE (using CLI flags only)"
  fi
fi

log "Running pre-flight checks..."

# Check snow CLI
if ! command -v snow &> /dev/null; then
  fatal "Snowflake CLI (snow) not found. Install: https://docs.snowflake.com/en/developer-guide/snowflake-cli/installation"
fi
ok "Snowflake CLI found: $(snow --version 2>/dev/null | head -1)"

# Detect/verify connection
if [[ "$DRY_RUN" == false ]]; then
  detect_connection
  ok "Snowflake connection: '$CONNECTION'"
else
  # In dry-run, just pick any connection for display
  if [[ -z "$CONNECTION" ]]; then
    CONNECTION="(auto-detect)"
  fi
fi

# Check Node.js (needed for app)
if [[ "$SKIP_APP" == false ]]; then
  if ! command -v node &> /dev/null; then
    fatal "Node.js not found (required for app deployment). Install Node.js >= 20"
  fi
  NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
  if [[ "$NODE_VERSION" -lt 20 ]]; then
    fatal "Node.js >= 20 required, found: $(node --version)"
  fi
  ok "Node.js $(node --version)"
fi

# Check NVIDIA key
if [[ "$SKIP_PREREQS" == false && -z "$NVIDIA_KEY" ]]; then
  warn "No NVIDIA API key provided. The secret will be created with a placeholder."
  warn "Set it later: ALTER SECRET SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET SET SECRET_STRING='your-key'"
  echo ""
fi

if [[ "$SKIP_PREREQS" == false && -z "$NGC_KEY" ]]; then
  warn "No NGC API key provided. SPCS NIM containers will not be able to pull weights."
  warn "Set it later: ALTER SECRET SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY SET SECRET_STRING='your-key'"
  warn "Get one at: https://org.ngc.nvidia.com/setup/personal-keys (select 'NGC Catalog' scope)"
  echo ""
fi

warn "Marketplace CKEs required for full functionality:"
warn "  - PubMed (biomedical literature search)"
warn "  - ClinicalTrials.gov (clinical trial data)"
warn "  Subscribe at: Snowsight > Marketplace > search for each name > Get"

echo ""
log "Configuration:"
log "  Connection:    $CONNECTION"
log "  Skip prereqs:  $SKIP_PREREQS"
log "  Skip data:     $SKIP_DATA"
log "  Skip app:      $SKIP_APP"
log "  Skip tests:    $SKIP_TESTS"
log "  Mirror NIMs:   $MIRROR_NIMS"
log "  Dry run:       $DRY_RUN"
log "  Backend only:  $BACKEND_ONLY"
log "  Agents/app only: $AGENTS_APP_ONLY"
log "  App only:      $APP_ONLY"
if [[ -n "$NVIDIA_KEY" ]]; then
  log "  NVIDIA key:    SET"
else
  log "  NVIDIA key:    NOT SET"
fi
if [[ -n "$NGC_KEY" ]]; then
  log "  NGC key:       SET"
else
  log "  NGC key:       NOT SET"
fi
echo ""

if [[ "$DRY_RUN" == false ]]; then
  # Non-interactive escape hatch. Without this the script blocks here forever in
  # CI or an agent session, and previously still returned success, making an
  # aborted run look like a completed one.
  if [[ "${SWB_ASSUME_YES:-}" == "1" ]]; then
    log "SWB_ASSUME_YES=1 set, proceeding without prompt"
    confirm=y
  else
    read -rp "Proceed with deployment? [y/N] " confirm
  fi
  if [[ ! "$confirm" =~ ^[Yy] ]]; then
    log "Aborted."
    exit 0
  fi
fi

echo ""
SECONDS=0

# =============================================================================
# PHASE 1: Snowflake Infrastructure (SQL Setup Scripts)
# =============================================================================
log "═══ PHASE 1: Snowflake Infrastructure ═══"
echo ""

if [[ "$AGENTS_APP_ONLY" == true ]]; then
  log "Skipping infrastructure in agents-app-only mode"
else

# Step 1 FIRST: Create databases and schemas (needed before prerequisites)
# Prerequisites references SCIENTIFIC_WORKBENCH.CATALOG for the secret path,
# so the database must exist first.
log "Step 1/11: Databases and schemas"
run_sql "$SCRIPT_DIR/setup/01-databases-and-schemas.sql" "SYSADMIN" "" "Create databases and schemas"

# Step 2: Warehouses and Compute Pools (needed for subsequent steps)
log "Step 2/11: Warehouses and compute pools"
run_sql "$SCRIPT_DIR/setup/02-warehouses.sql" "SYSADMIN" "" "Create warehouses and compute pools"

# Step 0: Prerequisites (ACCOUNTADMIN) — after databases exist
if [[ "$SKIP_PREREQS" == false ]]; then
  log "Step 0/11: Prerequisites (network rules, EAI, secrets)"

  # If NVIDIA or NGC keys are provided, patch the SQL before running
  PREREQ_FILE="$SCRIPT_DIR/setup/00-prerequisites.sql"
  if [[ -n "$NVIDIA_KEY" || -n "$NGC_KEY" ]]; then
    TEMP_PREREQ=$(mktemp)
    cp "$PREREQ_FILE" "$TEMP_PREREQ"
    [[ -n "$NVIDIA_KEY" ]] && sed -i.bak "s|{{NVIDIA_API_KEY}}|${NVIDIA_KEY}|g" "$TEMP_PREREQ"
    [[ -n "$NGC_KEY" ]]    && sed -i.bak "s|{{NGC_API_KEY}}|${NGC_KEY}|g" "$TEMP_PREREQ"
    rm -f "$TEMP_PREREQ.bak"
    run_sql "$TEMP_PREREQ" "ACCOUNTADMIN" "WORKBENCH_XS" "Prerequisites (EAI, network rules, secrets)"
    rm -f "$TEMP_PREREQ"
  else
    run_sql "$PREREQ_FILE" "ACCOUNTADMIN" "WORKBENCH_XS" "Prerequisites (EAI, network rules, secrets — placeholder keys)"
  fi
else
  warn "Skipping prerequisites (--skip-prereqs)"
fi

# Step 3: RBAC
log "Step 3/11: Roles and grants"
run_sql "$SCRIPT_DIR/setup/03-rbac.sql" "ACCOUNTADMIN" "WORKBENCH_XS" "Create roles and grants"

# Step 5: Tool Registry (tables that Cortex Search depends on)
log "Step 5/11: Tool registry"
run_sql "$SCRIPT_DIR/setup/05-tool-registry.sql" "SYSADMIN" "WORKBENCH_XS" "Tool registry table and auto-discovery task"

# Step 6: Cortex Services (Search over TOOLS and ASSETS tables from step 5)
log "Step 6/11: Cortex services (Search, Agent, CKE)"
run_sql "$SCRIPT_DIR/setup/06-cortex-services.sql" "SYSADMIN" "WORKBENCH_XS" "Cortex Search, Agent, CKE subscriptions"

# Step 7: Governance
log "Step 7/11: Governance framework"
run_sql "$SCRIPT_DIR/setup/07-governance.sql" "SYSADMIN" "WORKBENCH_XS" "Provenance log, canary assertions"

# Step 8: Workflow Engine
log "Step 8/11: Workflow engine"
run_sql "$SCRIPT_DIR/setup/08-workflow-engine.sql" "SYSADMIN" "WORKBENCH_XS" "Template+Agent workflow engine"

# Step 9: Tool Knowledge (rich per-tool guidance for agents)
log "Step 9/11: Tool knowledge"
run_sql "$SCRIPT_DIR/setup/12-tool-knowledge.sql" "SYSADMIN" "WORKBENCH_XS" "Tool knowledge table"

# Step 10: Agent tool dispatcher (EXECUTE_TOOL_BY_NAME, called by the Discovery Agent)
log "Step 10/11: Agent tool dispatcher"
run_sql "$SCRIPT_DIR/setup/13-execute-tool-by-name.sql" "SYSADMIN" "WORKBENCH_XS" "EXECUTE_TOOL_BY_NAME dispatcher"

# Step 11: Validation Test Suite (creates RUN_VALIDATION_TESTS SP for Phase 7)
log "Step 11/11: Validation test suite"
run_sql "$SCRIPT_DIR/setup/11-validation-tests.sql" "SYSADMIN" "WORKBENCH_XS" "Validation test SP"

echo ""
ok "Phase 1 complete: Infrastructure deployed"
echo ""
fi

# =============================================================================
# PHASE 1b: NIM Image Mirroring (optional)
# =============================================================================
if [[ "$MIRROR_NIMS" == true ]]; then
  log "═══ PHASE 1b: NIM Image Mirroring ═══"
  echo ""

  if [[ -z "$NGC_KEY" ]]; then
    err "NIM image mirroring requires --ngc-key (or NGC_API_KEY env var)"
    fatal "Cannot mirror images without NGC authentication"
  fi

  # Get the image repository URL
  REPO_URL=$(snow sql --connection "$CONNECTION" --role SYSADMIN --warehouse WORKBENCH_XS \
    --query "SHOW IMAGE REPOSITORIES IN SCHEMA SCIENTIFIC_WORKBENCH.CATALOG" --format json 2>/dev/null \
    | python3 -c "import json,sys; data=json.load(sys.stdin); print([r['repository_url'] for r in data if 'nim_gpu_images' in r.get('repository_url','').lower()][0])" 2>/dev/null || true)

  if [[ -z "$REPO_URL" ]]; then
    err "Could not find NIM_GPU_IMAGES repository URL."
    err "Ensure 02-warehouses.sql created the image repository."
    warn "Skipping NIM mirroring. Run tools/nvidia/mirror_nim_images.sql manually."
    warn "Mirroring needs an NGC-scoped key AND a running Docker daemon. Pull by amd64"
    warn "digest: Docker on Apple Silicon pulls arm64 and SPCS containers then fail with"
    warn "'exec format error'. NIM tools route to the NVIDIA hosted API until mirrored."
  elif [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would mirror NIM images to: $REPO_URL"
  else
    log "Image repository: $REPO_URL"
    log "Mirroring NIM images from nvcr.io (this takes 60-120 min)..."

    # Login to Snowflake registry
    snow spcs image-registry login --connection "$CONNECTION" 2>/dev/null || warn "Registry login may have failed"

    # Mirror each image
    NIM_IMAGES=(
      "nvcr.io/nim/mit/boltz2:1.8.0|boltz2:1.8.0"
      "nvcr.io/nim/nvidia/genmol:latest|genmol:latest"
      "nvcr.io/nim/mit/diffdock:latest|diffdock:latest"
      "nvcr.io/nim/nvidia/proteinmpnn:latest|proteinmpnn:latest"
      "nvcr.io/nim/nvidia/rfdiffusion:2.3.0|rfdiffusion:2.3.0"
      "nvcr.io/nim/nvidia/molmim:latest|molmim:latest"
      "nvcr.io/nim/nvidia/openfold2:latest|openfold2:latest"
      "nvcr.io/nim/nvidia/openfold3:latest|openfold3:latest"
      "nvcr.io/nim/nvidia/msa-search:latest|msa-search:latest"
    )

    for entry in "${NIM_IMAGES[@]}"; do
      src="${entry%%|*}"
      tag="${entry##*|}"
      dest="$REPO_URL/$tag"
      log "  Mirroring: $src -> $dest"
      if docker pull "$src" 2>/dev/null && docker tag "$src" "$dest" 2>/dev/null && docker push "$dest" 2>/dev/null; then
        ok "  $tag"
      else
        warn "  Failed to mirror $tag — run manually: docker pull $src && docker tag $src $dest && docker push $dest"
      fi
    done
  fi

  echo ""
  ok "Phase 1b complete: NIM image mirroring"
  echo ""
else
  log "Skipping NIM image mirroring (use --mirror-nims to enable)"
  echo ""
fi

# =============================================================================
# PHASE 2: Reference Data Loading
# =============================================================================
if [[ "$SKIP_DATA" == false ]]; then
  log "═══ PHASE 2: Reference Data Loading ═══"
  echo ""
  log "Loading reference datasets (this may take 30-45 minutes)..."

  for loader in "$SCRIPT_DIR"/data/loaders/*.sql; do
    name=$(basename "$loader" .sql)
    run_sql "$loader" "SYSADMIN" "WORKBENCH_ML" "Load: $name"
  done

  # Load synthetic demo data
  if [[ -f "$SCRIPT_DIR/data/synthetic/load_synthetic_data.sql" ]]; then
    run_sql "$SCRIPT_DIR/data/synthetic/load_synthetic_data.sql" "SYSADMIN" "WORKBENCH_S" "Load: synthetic demo data"
  fi

  echo ""
  # Seed asset catalog with reference datasets
  run_sql_inline "CALL SCIENTIFIC_WORKBENCH.CATALOG.SEED_ASSETS();" "SYSADMIN" "WORKBENCH_XS" "Seed asset catalog (reference data)"
  # Verify reference data row counts
  run_sql "$SCRIPT_DIR/setup/04-reference-data.sql" "SYSADMIN" "WORKBENCH_ML" "Verify: reference data counts"
  ok "Phase 2 complete: Reference data loaded"
  echo ""
else
  warn "Skipping Phase 2: Reference data (--skip-data)"
  echo ""
fi

# =============================================================================
# PHASE 3: Tools Deployment
# =============================================================================
log "═══ PHASE 3: Tools Deployment ═══"
echo ""

if [[ "$AGENTS_APP_ONLY" == true ]]; then
  log "Skipping tools in agents-app-only mode"
else

# Native Snowpark Python tools
log "Deploying native tools (Snowpark Python procedures)..."
if [[ "$BACKEND_ONLY" == false ]]; then
  for tool in "$SCRIPT_DIR"/tools/native/*.sql; do
    name=$(basename "$tool" .sql)
    run_sql "$tool" "SYSADMIN" "WORKBENCH_S" "Tool: $name"
  done
else
  log "Skipping native tools in backend-only mode"
fi

# NVIDIA NIM wrapper tools
log "Deploying NVIDIA NIM tools..."
for tool in "$SCRIPT_DIR"/tools/nvidia/*.sql; do
  name=$(basename "$tool" .sql)
  if [[ "$BACKEND_ONLY" == true && "$name" == "mirror_nim_images" ]]; then
    log "Skipping NIM image-mirroring helper in backend-only mode"
    continue
  fi
  if [[ "$name" == "mirror_nim_images" ]]; then
    log "Skipping mirror_nim_images.sql (utility, not a tool procedure)"
    continue
  fi
  run_sql "$tool" "SYSADMIN" "WORKBENCH_XS" "Tool: $name"
done

# Search tools
log "Deploying search tools..."
for tool in "$SCRIPT_DIR"/tools/search/*.sql; do
  name=$(basename "$tool" .sql)
  run_sql "$tool" "SYSADMIN" "WORKBENCH_XS" "Tool: $name"
done

# BYOT (Bring Your Own Tool) infrastructure
log "Deploying BYOT custom tool onboarding..."
run_sql "$SCRIPT_DIR/setup/14-custom-tool-onboarding.sql" "SYSADMIN" "WORKBENCH_XS" "BYOT onboarding infrastructure"

echo ""
ok "Phase 3 complete: All tools deployed"

# Seed asset catalog with tools (reference datasets seeded in Phase 2)
run_sql_inline "CALL SCIENTIFIC_WORKBENCH.CATALOG.SEED_ASSETS();" "SYSADMIN" "WORKBENCH_XS" "Seed asset catalog (tools)"
echo ""
fi

# =============================================================================
# PHASE 3.5: Notebooks
# =============================================================================
log "═══ Phase 3.5: Notebooks ═══"
echo ""

if [[ "$APP_ONLY" == true || "$AGENTS_APP_ONLY" == true ]]; then
  log "Skipping notebooks in app/agents-only mode"
else
  # Create shared workspace for notebooks
  run_sql_inline "CREATE WORKSPACE IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.SCIENTIFIC_WORKBENCH_NOTEBOOKS COMMENT = 'Scientific Workbench analysis notebooks'" "SYSADMIN" "WORKBENCH_XS" "Create notebooks workspace"
  run_sql_inline "GRANT READ, WRITE ON WORKSPACE SCIENTIFIC_WORKBENCH.CATALOG.SCIENTIFIC_WORKBENCH_NOTEBOOKS TO ROLE WORKBENCH_ADMIN" "SYSADMIN" "WORKBENCH_XS" "Grant workspace write to admin" || true
  run_sql_inline "GRANT READ ON WORKSPACE SCIENTIFIC_WORKBENCH.CATALOG.SCIENTIFIC_WORKBENCH_NOTEBOOKS TO ROLE WORKBENCH_SCIENTIST" "SYSADMIN" "WORKBENCH_XS" "Grant workspace read to scientist" || true

  # Upload notebook files and helpers to the workspace
  notebook_count=0
  WS_PATH="SCIENTIFIC_WORKBENCH.CATALOG.SCIENTIFIC_WORKBENCH_NOTEBOOKS:/"
  for nb_file in "$SCRIPT_DIR"/notebooks/*.ipynb "$SCRIPT_DIR"/notebooks/*.py; do
    [[ -f "$nb_file" ]] || continue
    nb_basename=$(basename "$nb_file")

    if [[ "$DRY_RUN" == true ]]; then
      log "[DRY-RUN] Would upload $nb_basename to workspace"
    else
      log "Uploading: $nb_basename"
      cortex ws cp "$nb_file" "$WS_PATH" --connection "$CONNECTION" 2>/dev/null || {
        # Fallback: use snow stage copy with overwrite
        snow stage copy "$nb_file" "snow://workspace/SCIENTIFIC_WORKBENCH.CATALOG.SCIENTIFIC_WORKBENCH_NOTEBOOKS/versions/live/" \
          --connection "$CONNECTION" --overwrite 2>/dev/null || warn "Failed to upload $nb_basename"
      }
      [[ "$nb_basename" == *.ipynb ]] && notebook_count=$((notebook_count + 1))
    fi
  done

  # Commit workspace to make files visible to other roles
  if [[ "$DRY_RUN" == false ]]; then
    run_sql_inline "ALTER WORKSPACE SCIENTIFIC_WORKBENCH.CATALOG.SCIENTIFIC_WORKBENCH_NOTEBOOKS COMMIT" "SYSADMIN" "WORKBENCH_XS" "Publish workspace"
  fi

  ok "Phase 3.5 complete: ${notebook_count} notebooks deployed to workspace"
fi
echo ""

# =============================================================================
# PHASE 4: Agents
# =============================================================================
log "═══ PHASE 4: Agents ═══"
echo ""

if [[ "$APP_ONLY" == true ]]; then
  log "Skipping agents in app-only mode"
else

# Deploy legacy agents in numbered order unless the router backend is isolated.
if [[ "$BACKEND_ONLY" == false ]]; then
  for agent in "$SCRIPT_DIR"/engine/sql/agents/[0-9]*.sql; do
    name=$(basename "$agent" .sql)
    run_sql "$agent" "SYSADMIN" "WORKBENCH_XS" "Agent: $name"
  done
  # Grant usage on all legacy agents (after all are created to avoid forward references)
  for agent_name in GENOMICS_AGENT CHEMISTRY_AGENT STRUCTURAL_AGENT CLINICAL_AGENT ORCHESTRATOR_AGENT WORKFLOW_AGENT; do
    run_sql_inline "GRANT USAGE ON AGENT SCIENTIFIC_WORKBENCH.CATALOG.${agent_name} TO ROLE WORKBENCH_SCIENTIST" "SYSADMIN" "WORKBENCH_XS" "Grant ${agent_name} usage" || true
  done
fi

# BioNeMo integration
if [[ "$BACKEND_ONLY" == false && -f "$SCRIPT_DIR/engine/sql/agents/bionemo_integration.sql" ]]; then
  run_sql "$SCRIPT_DIR/engine/sql/agents/bionemo_integration.sql" "SYSADMIN" "WORKBENCH_XS" "Agent: BioNeMo integration"
fi

if [[ -d "$SCRIPT_DIR/skills" && -d "$SCRIPT_DIR/cortex_project" ]]; then
  run_sql_inline "CREATE STAGE IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.AGENT_SKILLS DIRECTORY = (ENABLE = TRUE)" "SYSADMIN" "WORKBENCH_XS" "Agent skills stage"
  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would upload scientific skills and deploy four Agent Studio specs"
  else
    snow stage copy "$SCRIPT_DIR/skills" "@SCIENTIFIC_WORKBENCH.CATALOG.AGENT_SKILLS/skills/" --connection "$CONNECTION" --recursive --overwrite
    agent_specs=(
      "computational_biology:COMPUTATIONAL_BIOLOGY_AGENT"
      "medicinal_chemistry:MEDICINAL_CHEMISTRY_AGENT"
      "structural_biology:STRUCTURAL_BIOLOGY_AGENT"
      "custom_tools:CUSTOM_TOOLS_AGENT"
      "scientific_workbench_router:SCIENTIFIC_WORKBENCH_ROUTER"
    )
    for agent_entry in "${agent_specs[@]}"; do
      agent_name="${agent_entry%%:*}"
      agent_fqn="${agent_entry##*:}"
      yaml_file="$SCRIPT_DIR/cortex_project/${agent_name}.agent.yaml"
      if [[ ! -f "$yaml_file" ]]; then
        warn "Agent spec not found: $yaml_file"
        continue
      fi
      yaml_content=$(cat "$yaml_file")
      sql_stmt="CREATE OR REPLACE AGENT SCIENTIFIC_WORKBENCH.CATALOG.${agent_fqn}
  COMMENT = 'Agent Studio: ${agent_fqn}'
  FROM SPECIFICATION
\$\$
${yaml_content}
\$\$;"
      run_sql_inline "$sql_stmt" "SYSADMIN" "WORKBENCH_XS" "Agent Studio: ${agent_fqn}"
    done
    run_sql_inline "GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE WORKBENCH_SCIENTIST" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant Cortex Agent access"
    run_sql_inline "GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE WORKBENCH_SCIENTIST" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant Cortex model access"
    for agent_name in COMPUTATIONAL_BIOLOGY_AGENT MEDICINAL_CHEMISTRY_AGENT STRUCTURAL_BIOLOGY_AGENT CUSTOM_TOOLS_AGENT SCIENTIFIC_WORKBENCH_ROUTER; do
      run_sql_inline "GRANT USAGE ON AGENT SCIENTIFIC_WORKBENCH.CATALOG.${agent_name} TO ROLE WORKBENCH_SCIENTIST" "SYSADMIN" "WORKBENCH_XS" "Grant ${agent_name} usage"
    done
    if [[ "$BACKEND_ONLY" == true ]]; then
      run_sql_inline "GRANT CALLER USAGE ON DATABASE SCIENTIFIC_WORKBENCH TO ROLE SYSADMIN" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant app caller database access"
      run_sql_inline "GRANT INHERITED CALLER USAGE ON ALL SCHEMAS IN DATABASE SCIENTIFIC_WORKBENCH TO ROLE SYSADMIN" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant app caller schema access"
      run_sql_inline "GRANT INHERITED CALLER USAGE ON ALL AGENTS IN SCHEMA SCIENTIFIC_WORKBENCH.CATALOG TO ROLE SYSADMIN" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant app caller agent access"
      run_sql_inline "GRANT INHERITED CALLER USAGE ON ALL PROCEDURES IN SCHEMA SCIENTIFIC_WORKBENCH.CATALOG TO ROLE SYSADMIN" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant app caller procedure access"
      run_sql_inline "GRANT CALLER READ ON STAGE SCIENTIFIC_WORKBENCH.CATALOG.AGENT_SKILLS TO ROLE SYSADMIN" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant app caller skill access"
      run_sql_inline "GRANT CALLER USAGE ON WAREHOUSE WORKBENCH_S TO ROLE SYSADMIN" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant app caller warehouse access"
    fi
  fi
fi

echo ""
ok "Phase 4 complete: Agents deployed"
echo ""
fi

# =============================================================================
# PHASE 5: Semantic Views + Discovery Agent
# =============================================================================
log "═══ PHASE 5: Semantic Views ═══"
echo ""

if [[ "$AGENTS_APP_ONLY" == true ]]; then
  log "Skipping semantic views in agents-app-only mode"
else

if [[ "$BACKEND_ONLY" == false ]]; then
  for sv in "$SCRIPT_DIR"/data/semantic_views/*.sql; do
    name=$(basename "$sv" .sql)
    run_sql "$sv" "SYSADMIN" "WORKBENCH_XS" "Semantic view: $name"
  done
fi

# Discovery Agent (depends on semantic views + search services)
if [[ "$BACKEND_ONLY" == false && -f "$SCRIPT_DIR/engine/sql/create_workflow_runner.sql" ]]; then
  run_sql "$SCRIPT_DIR/engine/sql/create_workflow_runner.sql" "SYSADMIN" "WORKBENCH_XS" "Discovery Agent + workflow runner"
fi

echo ""
ok "Phase 5 complete: Semantic views + Discovery Agent created"
echo ""
fi

# =============================================================================
# PHASE 6: App Deployment (Snowflake App Runtime)
# =============================================================================
if [[ "$SKIP_APP" == false ]]; then
  log "═══ PHASE 6: App Deployment (SAR) ═══"
  echo ""

  APP_DIR="$SCRIPT_DIR/app"

  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] Would deploy app from: $APP_DIR via snow app deploy"
  else
    log "Deploying Next.js app to Snowflake App Runtime..."

    cd "$APP_DIR"

    # Deploy using Snowflake CLI (v3.17+ required for SAR)
    snow app deploy --connection "$CONNECTION" 2>&1 || {
      err "SAR deployment failed."
      err "  Troubleshoot:"
      err "    1. Verify snow CLI >= 3.17: snow --version"
      err "    2. Check snowflake.yml has type: snowflake-app"
      err "    3. Check app.yml has install/build/run phases"
      err "    4. Try: snow app deploy --connection $CONNECTION --verbose"
      cd "$SCRIPT_DIR"
      exit 1
    }

    cd "$SCRIPT_DIR"

    # Get app URL
    APP_URL=$(snow app open --connection "$CONNECTION" --print-only 2>/dev/null || true)

    if [[ -n "${APP_URL:-}" ]]; then
      ok "App URL: $APP_URL"
    fi
  fi

  # Grant app access to WORKBENCH_SCIENTIST
  run_sql_inline "GRANT USAGE ON APPLICATION SERVICE SNOWFLAKE_APPS.PUBLIC.SCIENTIFIC_WORKBENCH_APP TO ROLE WORKBENCH_SCIENTIST" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant app access to WORKBENCH_SCIENTIST" || true
  run_sql_inline "GRANT USAGE ON DATABASE SNOWFLAKE_APPS TO ROLE WORKBENCH_SCIENTIST" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant SNOWFLAKE_APPS database access" || true
  run_sql_inline "GRANT USAGE ON SCHEMA SNOWFLAKE_APPS.PUBLIC TO ROLE WORKBENCH_SCIENTIST" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant SNOWFLAKE_APPS schema access" || true
  run_sql_inline "GRANT USAGE ON WAREHOUSE SNOWFLAKE_APPS_QUERY_WH TO ROLE WORKBENCH_SCIENTIST" "ACCOUNTADMIN" "WORKBENCH_XS" "Grant app query warehouse access" || true

  echo ""
  ok "Phase 6 complete: App deployed via SAR"
  echo ""
else
  warn "Skipping Phase 6: App deployment (--skip-app)"
  echo ""
fi

# =============================================================================
# PHASE 7: Verification
# =============================================================================
if [[ "$SKIP_TESTS" == false && "$BACKEND_ONLY" == false && "$APP_ONLY" == false ]]; then
  log "═══ PHASE 7: Verification ═══"
  echo ""

  TESTS_PASSED=0
  TESTS_FAILED=0

  # Run SQL test files
  for test in "$SCRIPT_DIR"/tests/*.sql; do
    name=$(basename "$test" .sql)
    if run_sql "$test" "WORKBENCH_ADMIN" "WORKBENCH_XS" "Test: $name"; then
      TESTS_PASSED=$((TESTS_PASSED + 1))
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
  done

  # Run the comprehensive validation procedure
  log "Running validation test suite..."
  VALIDATION_OUTPUT=$(snow sql --connection "$CONNECTION" --role ACCOUNTADMIN --warehouse WORKBENCH_XS \
    --query "CALL SCIENTIFIC_WORKBENCH.CATALOG.RUN_VALIDATION_TESTS()" --format json 2>/dev/null || echo '[]')

  if echo "$VALIDATION_OUTPUT" | python3 -c "
import json, sys
try:
    rows = json.load(sys.stdin)
    checks = [r for r in rows if r.get('TEST_GROUP') != 'SUMMARY']
    summary = next((r for r in rows if r.get('TEST_GROUP') == 'SUMMARY'), None)
    if not checks:
        raise ValueError('no rows')
except Exception:
    print('Could not parse validation results')
    sys.exit(1)
failed = [r for r in checks if r.get('STATUS') == 'FAIL']
for r in failed:
    print('    FAIL  %s: %s (%s)' % (r.get('TEST_GROUP'), r.get('TEST_NAME'), r.get('DETAIL')))
print('    ' + (summary.get('DETAIL', '') if summary else '%d checks, %d failed' % (len(checks), len(failed))))
sys.exit(1 if failed else 0)
"; then
    ok "Validation test suite: ALL PASS"
  else
    warn "Validation test suite: some checks failed (review output above)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi

  echo ""
  if [[ "$TESTS_FAILED" -eq 0 ]]; then
    ok "All $TESTS_PASSED tests passed"
  else
    warn "$TESTS_PASSED passed, $TESTS_FAILED failed"
    warn "Review failed tests above. Non-critical failures may be due to --skip-data."
  fi
  echo ""
else
  warn "Skipping Phase 7: Verification (--skip-tests)"
  echo ""
fi

# =============================================================================
# Summary
# =============================================================================
ELAPSED=$SECONDS
MINS=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   Deployment Complete                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
log "Duration: ${MINS}m ${SECS}s"
echo ""
log "Deployed:"
log "  - 3 databases, 12 schemas"
log "  - 3 warehouses, 6 compute pools (3 app + 3 NIM: L40S, A10G, build)"
log "  - 3 roles (WORKBENCH_ADMIN, WORKBENCH_SCIENTIST, WORKBENCH_VIEWER)"
log "  - 23 registered tools (8 native + 10 NVIDIA NIM + 2 NIM pipelines + 3 search)"
log "  - 6 notebooks (drug discovery, genomics, clinical, molecular, structural, scRNA)"
log "  - 12 Cortex Agents (domain, orchestrator, workflow, discovery, router, Agent Studio)"
log "  - 4 workflow templates"
log "  - 4 semantic views"
log "  - NIM_ENDPOINTS config table (11 endpoints, dual-mode routing)"
log "  - Tool knowledge table (per-tool agent guidance)"
log "  - Validation test suite: CALL CATALOG.RUN_VALIDATION_TESTS()"
[[ "$SKIP_APP" == false ]] && log "  • Next.js app (Snowflake App Runtime)"
echo ""
log "Next steps:"
if [[ -z "$NVIDIA_KEY" && "$SKIP_PREREQS" == false ]]; then
  log "  1. Set your NVIDIA API key:"
  log "     ALTER SECRET SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET SET SECRET_STRING='your-key';"
fi
if [[ -z "$NGC_KEY" && "$SKIP_PREREQS" == false ]]; then
  log "  2. Set your NGC API key (required for SPCS NIM containers):"
  log "     ALTER SECRET SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY SET SECRET_STRING='your-key';"
fi
log "  • Grant WORKBENCH_SCIENTIST to users: GRANT ROLE WORKBENCH_SCIENTIST TO USER <username>;"
log "  • Subscribe to CKEs in Marketplace: PubMed, ClinicalTrials.gov"
[[ "$SKIP_APP" == false && -n "${APP_URL:-}" ]] && log "  • Open the app: $APP_URL"
echo ""
