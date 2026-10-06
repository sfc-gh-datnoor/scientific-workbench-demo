#!/usr/bin/env bash
# =============================================================================
# teardown.sh — Complete teardown of Snowflake Scientific Workbench
# =============================================================================
# DISCLAIMER: This application is not part of the Snowflake Service and is
# governed by the terms in LICENSE, unless expressly agreed to in writing. You
# use this application at your own risk, and Snowflake has no obligation to
# support your use of this application.
# =============================================================================
#
# Usage:
#   ./teardown.sh [OPTIONS]
#
# Options:
#   --connection NAME   Snowflake CLI connection name
#   --keep-data         Keep WORKBENCH_REFERENCE and WORKBENCH_PROJECTS databases
#   --dry-run           Print what would be dropped without executing
#   -y, --yes           Skip confirmation prompt
#   -h, --help          Show this help
#
# WARNING: This script drops ALL objects created by deploy.sh. This is
# irreversible. All data, procedures, agents, services, and roles will
# be permanently deleted.
# =============================================================================

set -euo pipefail

CONNECTION=""
KEEP_DATA=false
DRY_RUN=false
AUTO_YES=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
err()  { echo -e "${RED}  ✗${NC} $*" >&2; }

usage() {
  sed -n '2,/^# ====/p' "$0" | grep '^#' | sed 's/^# \?//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --connection)  CONNECTION="$2"; shift 2 ;;
    --keep-data)   KEEP_DATA=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    -y|--yes)      AUTO_YES=true; shift ;;
    -h|--help)     usage ;;
    *)             err "Unknown option: $1"; usage ;;
  esac
done

# Auto-detect connection if not specified
if [[ -z "$CONNECTION" ]]; then
  CONNECTION=$(snow connection list --format json 2>/dev/null | python3 -c "
import json, sys
conns = json.load(sys.stdin)
for c in conns:
    if c.get('is_default'): print(c['connection_name']); break
" 2>/dev/null || true)
  if [[ -z "$CONNECTION" ]]; then
    err "No connection specified and no default found. Use --connection NAME."
    exit 1
  fi
fi

run_sql() {
  local sql="$1"
  local desc="${2:-}"
  if [[ "$DRY_RUN" == true ]]; then
    log "[DRY-RUN] $desc"
    echo "  $sql"
    return 0
  fi
  local output
  output=$(snow sql --connection "$CONNECTION" --role ACCOUNTADMIN -q "$sql" 2>&1) || true
  if echo "$output" | grep -qi "error\|does not exist"; then
    # Silently ignore "does not exist" errors during teardown
    if echo "$output" | grep -qi "does not exist"; then
      ok "$desc (already gone)"
    else
      warn "$desc — $output"
    fi
  else
    ok "$desc"
  fi
}

echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║          TEARDOWN — Snowflake Scientific Workbench          ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "Connection: $CONNECTION"
log "Keep data:  $KEEP_DATA"
log "Dry run:    $DRY_RUN"
echo ""

if [[ "$AUTO_YES" != true && "$DRY_RUN" != true ]]; then
  echo -e "${RED}WARNING: This will permanently delete ALL workbench objects.${NC}"
  echo -e "${RED}This action cannot be undone.${NC}"
  echo ""
  read -rp "Type 'TEARDOWN' to confirm: " confirm
  if [[ "$confirm" != "TEARDOWN" ]]; then
    echo "Aborted."
    exit 0
  fi
  echo ""
fi

# ─── Phase 1: Suspend tasks ───────────────────────────────────────────────
log "Phase 1: Suspending tasks..."
run_sql "ALTER TASK IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.TASK_AUTO_DISCOVER_TOOLS SUSPEND" "Suspend auto-discover task"
run_sql "ALTER TASK IF EXISTS SCIENTIFIC_WORKBENCH.GOVERNANCE.TASK_RUN_CANARIES SUSPEND" "Suspend canary task"

# ─── Phase 2: Drop SAR app ────────────────────────────────────────────────
log "Phase 2: Dropping SAR application..."
run_sql "DROP APPLICATION SERVICE IF EXISTS SNOWFLAKE_APPS.PUBLIC.SCIENTIFIC_WORKBENCH_APP" "Drop SAR app service"

# ─── Phase 3: Drop SPCS services ──────────────────────────────────────────
log "Phase 3: Dropping SPCS services..."
run_sql "DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_BOLTZ2_SVC" "Drop Boltz2 NIM service"
run_sql "DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.WORKBENCH_APP_SERVICE" "Drop workbench app service"
run_sql "DROP SERVICE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.SCIENTIFIC_WORKBENCH_WEB" "Drop workbench web service"

# ─── Phase 4: Drop agents ─────────────────────────────────────────────────
log "Phase 4: Dropping Cortex agents..."
for agent in SCIENTIFIC_WORKBENCH_ROUTER COMPUTATIONAL_BIOLOGY_AGENT MEDICINAL_CHEMISTRY_AGENT \
             STRUCTURAL_BIOLOGY_AGENT CUSTOM_TOOLS_AGENT ORCHESTRATOR_AGENT DISCOVERY_AGENT \
             GENOMICS_AGENT CHEMISTRY_AGENT STRUCTURAL_AGENT CLINICAL_AGENT WORKFLOW_AGENT; do
  run_sql "DROP AGENT IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.${agent}" "Drop agent: $agent"
done

# ─── Phase 5: Drop integrations ───────────────────────────────────────────
log "Phase 5: Dropping external access integrations..."
for eai in NVIDIA_API_EAI NGC_REGISTRY_PULL_EAI NIM_RUNTIME_EAI PDB_API_EAI CUSTOM_API_EAI; do
  run_sql "DROP INTEGRATION IF EXISTS $eai" "Drop integration: $eai"
done

# ─── Phase 6: Drop network rules and secrets ──────────────────────────────
log "Phase 6: Dropping network rules and secrets..."
for rule in NVIDIA_API_NETWORK_RULE NGC_REGISTRY_PULL NIM_RUNTIME_EGRESS PDB_API_RULE CUSTOM_API_NETWORK_RULE; do
  run_sql "DROP NETWORK RULE IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.${rule}" "Drop rule: $rule"
done
run_sql "DROP SECRET IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET" "Drop NVIDIA API secret"
run_sql "DROP SECRET IF EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NGC_API_KEY" "Drop NGC API key"

# ─── Phase 7: Drop compute pools ──────────────────────────────────────────
log "Phase 7: Dropping compute pools..."
for pool in WORKBENCH_CPU_POOL WORKBENCH_APP_POOL NIM_GPU_A10G_POOL NIM_GPU_L40S_POOL NIM_BUILD_POOL; do
  run_sql "ALTER COMPUTE POOL IF EXISTS $pool STOP ALL" "Stop pool: $pool"
  run_sql "DROP COMPUTE POOL IF EXISTS $pool" "Drop pool: $pool"
done

# ─── Phase 8: Drop databases (cascades schemas, tables, procedures, etc.) ─
log "Phase 8: Dropping databases..."
run_sql "DROP DATABASE IF EXISTS SCIENTIFIC_WORKBENCH" "Drop SCIENTIFIC_WORKBENCH"
if [[ "$KEEP_DATA" == true ]]; then
  warn "Keeping WORKBENCH_REFERENCE and WORKBENCH_PROJECTS (--keep-data)"
else
  run_sql "DROP DATABASE IF EXISTS WORKBENCH_REFERENCE" "Drop WORKBENCH_REFERENCE"
  run_sql "DROP DATABASE IF EXISTS WORKBENCH_PROJECTS" "Drop WORKBENCH_PROJECTS"
fi
run_sql "DROP DATABASE IF EXISTS SNOWFLAKE_APPS" "Drop SNOWFLAKE_APPS"

# ─── Phase 9: Drop warehouses ─────────────────────────────────────────────
log "Phase 9: Dropping warehouses..."
for wh in WORKBENCH_XS WORKBENCH_S WORKBENCH_ML SNOWFLAKE_APPS_QUERY_WH; do
  run_sql "DROP WAREHOUSE IF EXISTS $wh" "Drop warehouse: $wh"
done

# ─── Phase 10: Drop roles ─────────────────────────────────────────────────
log "Phase 10: Dropping roles..."
for role in WORKBENCH_VIEWER WORKBENCH_SCIENTIST WORKBENCH_ADMIN; do
  run_sql "DROP ROLE IF EXISTS $role" "Drop role: $role"
done

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   Teardown Complete                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "All Scientific Workbench objects have been removed."
if [[ "$KEEP_DATA" == true ]]; then
  log "Reference and project data were preserved (--keep-data)."
fi
