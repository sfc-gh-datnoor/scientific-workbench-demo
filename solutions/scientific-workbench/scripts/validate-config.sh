#!/usr/bin/env bash
# =============================================================================
# validate-config.sh — Pre-flight validation for Scientific Workbench deployment
# Usage: bash setup/validate-config.sh [path/to/workbench.config.yaml]
# DISCLAIMER: This application is not part of the Snowflake Service and is
# governed by the terms in LICENSE, unless expressly agreed to in writing. You
# use this application at your own risk, and Snowflake has no obligation to
# support your use of this application.
# =============================================================================
set -euo pipefail

CONFIG="${1:-workbench.config.yaml}"
ERRORS=0
WARNS=0

red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

err()  { red  "  ERROR: $*"; ERRORS=$((ERRORS + 1)); }
warn() { yellow "  WARN:  $*"; WARNS=$((WARNS + 1)); }
ok()   { green "  OK:    $*"; }

# ---------------------------------------------------------------------------
# YAML parser (no yq dependency — grep/sed only)
# Usage: cfg_get "secrets.nvidia_api_key"
# Handles simple key: value pairs; does not support multi-line or anchors.
# ---------------------------------------------------------------------------
cfg_get() {
  local key="$1"
  # Split dotted key into parts
  local IFS='.'
  read -ra parts <<< "$key"

  local indent=0
  local found_parent=true
  local result=""

  if [[ ${#parts[@]} -eq 1 ]]; then
    result=$(grep -E "^${parts[0]}:" "$CONFIG" 2>/dev/null | head -1 | sed 's/^[^:]*:\s*//' | sed 's/\s*#.*//' | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
  else
    # Multi-level: find the parent block, then the child key
    local parent="${parts[0]}"
    local child="${parts[1]}"
    # Find the line number of the parent key
    local parent_line
    parent_line=$(grep -n "^${parent}:" "$CONFIG" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -z "$parent_line" ]]; then
      echo ""
      return
    fi
    # Search after the parent line for the child key (indented)
    result=$(tail -n +"$((parent_line + 1))" "$CONFIG" | \
      grep -E "^\s+${child}:" | head -1 | \
      sed 's/^[^:]*:\s*//' | sed 's/\s*#.*//' | \
      sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
  fi

  # Trim whitespace
  result=$(echo "$result" | xargs 2>/dev/null || echo "$result")
  echo "$result"
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
echo ""
bold "Scientific Workbench — Pre-Deployment Validation"
bold "Config: $CONFIG"
echo ""

# 1. Config file exists
if [[ ! -f "$CONFIG" ]]; then
  red "Config file not found: $CONFIG"
  echo "  Copy the template:  cp workbench.config.yaml.example workbench.config.yaml"
  exit 1
fi
ok "Config file found"

# 2. Snowflake connection
bold ""
bold "Snowflake Connection"
CONNECTION=$(cfg_get "snowflake.connection")
if [[ -z "$CONNECTION" ]]; then
  err "snowflake.connection is empty"
else
  ok "Connection name: $CONNECTION"
  if command -v snow &>/dev/null; then
    if snow connection test --connection "$CONNECTION" &>/dev/null; then
      ok "Connection test passed"
    else
      err "Connection test failed: snow connection test --connection $CONNECTION"
    fi
  else
    warn "snow CLI not found — cannot test connection (install: pip install snowflake-cli)"
  fi
fi

# 3. API keys
bold ""
bold "API Keys"
NVIDIA_KEY=$(cfg_get "secrets.nvidia_api_key")
NGC_KEY=$(cfg_get "secrets.ngc_api_key")

if [[ -z "$NVIDIA_KEY" || "$NVIDIA_KEY" == *"REPLACE_WITH"* ]]; then
  warn "secrets.nvidia_api_key is empty or placeholder — NIM tools will fail until set"
  warn "  Get key: https://build.nvidia.com > pick any model > Generate API Key"
else
  ok "NVIDIA API key: set (${#NVIDIA_KEY} chars)"
fi

if [[ -z "$NGC_KEY" || "$NGC_KEY" == *"REPLACE_WITH"* ]]; then
  warn "secrets.ngc_api_key is empty or placeholder — SPCS NIM mirroring will fail"
  warn "  Get key: https://ngc.nvidia.com/setup/personal-keys (select 'NGC Catalog' scope)"
else
  ok "NGC API key: set (${#NGC_KEY} chars)"
fi

# 4. Database names
bold ""
bold "Databases"
for db_key in workbench reference projects; do
  db_name=$(cfg_get "databases.${db_key}")
  if [[ -z "$db_name" ]]; then
    err "databases.${db_key} is empty"
  else
    ok "${db_key}: ${db_name}"
  fi
done

# 5. Warehouses
bold ""
bold "Warehouses"
for wh_key in xs small ml; do
  wh_name=$(cfg_get "warehouses.${wh_key}")
  if [[ -z "$wh_name" ]]; then
    err "warehouses.${wh_key} is empty"
  else
    ok "${wh_key}: ${wh_name}"
  fi
done

# 6. NIM services
bold ""
bold "NIM Services"
NIM_COUNT=0
for nim in boltz2 genmol diffdock rfdiffusion proteinmpnn molmim openfold2 openfold3 msa_search; do
  val=$(cfg_get "nim_services.${nim}")
  if [[ "$val" == "true" ]]; then
    ok "${nim}: enabled"
    NIM_COUNT=$((NIM_COUNT + 1))
  fi
done
if [[ "$NIM_COUNT" -eq 0 ]]; then
  warn "No NIM services enabled — all NIM tools will use hosted NVIDIA API only"
else
  echo "  $NIM_COUNT NIM service(s) will be mirrored to SPCS"
fi

# 7. Agents
bold ""
bold "Agents"
LEGACY=$(cfg_get "agents.deploy_legacy_sql")
STUDIO=$(cfg_get "agents.deploy_agent_studio")
if [[ "$LEGACY" == "true" ]]; then
  ok "Legacy SQL agents: enabled (8 agents)"
else
  warn "Legacy SQL agents: disabled"
fi
if [[ "$STUDIO" == "true" ]]; then
  ok "Agent Studio agents: enabled (4 agents + 7 skills)"
  if ! command -v cortex &>/dev/null; then
    warn "cortex CLI not found — Agent Studio deployment will fail"
    warn "  Install: pip install snowflake-cli[cortex]"
  fi
else
  warn "Agent Studio agents: disabled"
fi

# 8. Marketplace CKEs
bold ""
bold "Marketplace Subscriptions"
PUBMED=$(cfg_get "marketplace.pubmed_cke")
CT=$(cfg_get "marketplace.clinicaltrials_cke")
if [[ "$PUBMED" != "true" ]]; then
  warn "PubMed CKE not subscribed — search_pubmed tool will return no results"
  warn "  Subscribe: Snowsight > Marketplace > search 'PubMed' CKE > Get"
fi
if [[ "$CT" != "true" ]]; then
  warn "ClinicalTrials CKE not subscribed — search_clinical_trials tool will return no results"
  warn "  Subscribe: Snowsight > Marketplace > search 'ClinicalTrials' CKE > Get"
fi
if [[ "$PUBMED" == "true" ]]; then ok "PubMed CKE: subscribed"; fi
if [[ "$CT" == "true" ]]; then ok "ClinicalTrials CKE: subscribed"; fi

# 9. GPU instance families (if connected)
bold ""
bold "GPU Availability"
if command -v snow &>/dev/null && [[ -n "$CONNECTION" ]]; then
  GPU_FAMILIES=$(snow sql --connection "$CONNECTION" --role SYSADMIN \
    --query "SHOW COMPUTE POOL INSTANCE FAMILIES IN ACCOUNT" --format json 2>/dev/null || echo "[]")
  if [[ "$GPU_FAMILIES" != "[]" ]]; then
    for family in GPU_NV_S GPU_L40S_G1_16; do
      if echo "$GPU_FAMILIES" | grep -q "$family"; then
        ok "$family available in account"
      else
        warn "$family NOT available — NIMs requiring this GPU type cannot deploy"
      fi
    done
  else
    warn "Could not query GPU instance families (check SYSADMIN privileges)"
  fi
else
  warn "Skipping GPU check (no snow CLI or connection)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
bold "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$ERRORS" -gt 0 ]]; then
  red "VALIDATION FAILED: $ERRORS error(s), $WARNS warning(s)"
  echo "  Fix the errors above before deploying."
  exit 1
elif [[ "$WARNS" -gt 0 ]]; then
  yellow "VALIDATION PASSED with $WARNS warning(s)"
  echo "  Deployment will proceed but some features may be unavailable."
  exit 0
else
  green "VALIDATION PASSED — all checks OK"
  exit 0
fi
