#!/usr/bin/env bash
# =============================================================================
# 17-agent-studio.sh
# Deploy Agent Studio YAML agents + skills to Snowflake.
# DISCLAIMER: This application is not part of the Snowflake Service and is
# governed by the terms in LICENSE, unless expressly agreed to in writing. You
# use this application at your own risk, and Snowflake has no obligation to
# support your use of this application.
# Requires: `snow` CLI and `cortex` CLI (pip install snowflake-cli[cortex])
#
# Creates:
#   - AGENT_SKILLS stage + uploads 7 skill directories
#   - 4 YAML-based Cortex Agents:
#       COMPUTATIONAL_BIOLOGY_AGENT
#       MEDICINAL_CHEMISTRY_AGENT
#       STRUCTURAL_BIOLOGY_AGENT
#       SCIENTIFIC_WORKBENCH_ROUTER
#   - Grants for WORKBENCH_SCIENTIST role
#   - Caller-rights grants for SPCS app access (optional)
#
# Usage:
#   bash setup/17-agent-studio.sh [--connection <name>] [--config <path>] [--caller-grants]
#
# Prerequisites:
#   - setup/00 through 16 completed
#   - Tool procedures deployed (Phase 3)
#   - cortex CLI available
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-workbench.config.yaml}"
CONNECTION=""
CALLER_GRANTS=false
DATABASE="SCIENTIFIC_WORKBENCH"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --connection) CONNECTION="$2"; shift 2 ;;
    --config)     CONFIG="$2"; shift 2 ;;
    --caller-grants) CALLER_GRANTS=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Load config if available
# ---------------------------------------------------------------------------
if [[ -z "$CONNECTION" && -f "$CONFIG" ]]; then
  CONNECTION=$(grep -E '^\s+connection:' "$CONFIG" 2>/dev/null | head -1 | sed 's/^[^:]*:\s*//' | sed 's/\s*#.*//' | tr -d '"' | tr -d "'" | xargs)
fi
if [[ -f "$CONFIG" ]]; then
  db_val=$(grep -A5 '^databases:' "$CONFIG" | grep -E '^\s+workbench:' | head -1 | sed 's/^[^:]*:\s*//' | sed 's/\s*#.*//' | tr -d '"' | tr -d "'" | xargs)
  [[ -n "$db_val" ]] && DATABASE="$db_val"
fi

if [[ -z "$CONNECTION" ]]; then
  echo "ERROR: No connection specified. Use --connection <name> or set snowflake.connection in $CONFIG"
  exit 1
fi

log()  { echo "[$(date +%H:%M:%S)] $*"; }
ok()   { echo "[$(date +%H:%M:%S)] OK: $*"; }
err()  { echo "[$(date +%H:%M:%S)] ERROR: $*" >&2; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
log "Agent Studio deployment"
log "  Connection: $CONNECTION"
log "  Database:   $DATABASE"
log "  Config:     $CONFIG"
echo ""

if ! command -v snow &>/dev/null; then
  err "snow CLI not found. Install: pip install snowflake-cli"
  exit 1
fi

if ! command -v cortex &>/dev/null; then
  err "cortex CLI not found. Install: pip install snowflake-cli[cortex]"
  err "Agent Studio agents cannot be deployed without the cortex CLI."
  exit 1
fi

if [[ ! -d "$SCRIPT_DIR/skills" ]]; then
  err "skills/ directory not found at $SCRIPT_DIR/skills"
  exit 1
fi

if [[ ! -d "$SCRIPT_DIR/cortex_project" ]]; then
  err "cortex_project/ directory not found at $SCRIPT_DIR/cortex_project"
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Create AGENT_SKILLS stage
# ---------------------------------------------------------------------------
log "Step 1: Creating AGENT_SKILLS stage"
snow sql --connection "$CONNECTION" --role SYSADMIN --warehouse WORKBENCH_XS \
  --query "CREATE STAGE IF NOT EXISTS ${DATABASE}.CATALOG.AGENT_SKILLS DIRECTORY = (ENABLE = TRUE)" \
  2>/dev/null || { err "Failed to create AGENT_SKILLS stage"; exit 1; }
ok "AGENT_SKILLS stage ready"

# ---------------------------------------------------------------------------
# 2. Upload skills
# ---------------------------------------------------------------------------
log "Step 2: Uploading 7 skill directories to @AGENT_SKILLS/skills/"
snow stage copy "$SCRIPT_DIR/skills" "@${DATABASE}.CATALOG.AGENT_SKILLS/skills/" \
  --connection "$CONNECTION" --recursive --overwrite 2>/dev/null || {
  err "Failed to upload skills. Check connection and stage permissions."
  exit 1
}
ok "Skills uploaded"

# ---------------------------------------------------------------------------
# 3. Deploy 4 YAML agents
# ---------------------------------------------------------------------------
log "Step 3: Deploying Agent Studio agents"

AGENT_SPECS=(
  "computational_biology:COMPUTATIONAL_BIOLOGY_AGENT"
  "medicinal_chemistry:MEDICINAL_CHEMISTRY_AGENT"
  "structural_biology:STRUCTURAL_BIOLOGY_AGENT"
  "scientific_workbench_router:SCIENTIFIC_WORKBENCH_ROUTER"
)

for entry in "${AGENT_SPECS[@]}"; do
  agent_file="${entry%%:*}"
  agent_fqn="${entry##*:}"
  log "  Deploying ${agent_fqn}..."
  cortex agent-studio agent-deploy --connection "$CONNECTION" \
    --file-path "$SCRIPT_DIR/cortex_project/${agent_file}.agent.yaml" \
    --fqn "${DATABASE}.CATALOG.${agent_fqn}" 2>/dev/null || {
    err "Failed to deploy ${agent_fqn}"
    exit 1
  }
  ok "  ${agent_fqn}"
done

# ---------------------------------------------------------------------------
# 4. Grant USAGE on each agent
# ---------------------------------------------------------------------------
log "Step 4: Granting agent usage to WORKBENCH_SCIENTIST"
for entry in "${AGENT_SPECS[@]}"; do
  agent_fqn="${entry##*:}"
  snow sql --connection "$CONNECTION" --role SYSADMIN --warehouse WORKBENCH_XS \
    --query "GRANT USAGE ON AGENT ${DATABASE}.CATALOG.${agent_fqn} TO ROLE WORKBENCH_SCIENTIST" \
    2>/dev/null || true
done
ok "Agent grants applied"

# ---------------------------------------------------------------------------
# 5. Caller-rights grants (for SPCS app access)
# ---------------------------------------------------------------------------
if [[ "$CALLER_GRANTS" == true ]]; then
  log "Step 5: Applying caller-rights grants for SPCS app"
  GRANTS=(
    "GRANT CALLER USAGE ON DATABASE ${DATABASE} TO ROLE SYSADMIN"
    "GRANT INHERITED CALLER USAGE ON ALL SCHEMAS IN DATABASE ${DATABASE} TO ROLE SYSADMIN"
    "GRANT INHERITED CALLER USAGE ON ALL AGENTS IN SCHEMA ${DATABASE}.CATALOG TO ROLE SYSADMIN"
    "GRANT INHERITED CALLER USAGE ON ALL PROCEDURES IN SCHEMA ${DATABASE}.CATALOG TO ROLE SYSADMIN"
    "GRANT CALLER READ ON STAGE ${DATABASE}.CATALOG.AGENT_SKILLS TO ROLE SYSADMIN"
    "GRANT CALLER USAGE ON WAREHOUSE WORKBENCH_S TO ROLE SYSADMIN"
  )
  for grant_sql in "${GRANTS[@]}"; do
    snow sql --connection "$CONNECTION" --role ACCOUNTADMIN --warehouse WORKBENCH_XS \
      --query "$grant_sql" 2>/dev/null || true
  done
  ok "Caller-rights grants applied"
else
  log "Step 5: Skipping caller-rights grants (use --caller-grants to enable)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
ok "Agent Studio deployment complete"
log "  4 agents deployed to ${DATABASE}.CATALOG"
log "  7 skills uploaded to @${DATABASE}.CATALOG.AGENT_SKILLS/skills/"
log ""
log "Agents:"
log "  - COMPUTATIONAL_BIOLOGY_AGENT (3 tools, 3 skills)"
log "  - MEDICINAL_CHEMISTRY_AGENT   (4 tools, 3 skills)"
log "  - STRUCTURAL_BIOLOGY_AGENT    (7 tools, 4 skills)"
log "  - SCIENTIFIC_WORKBENCH_ROUTER (3 agent_toolsets, 7 skills)"
