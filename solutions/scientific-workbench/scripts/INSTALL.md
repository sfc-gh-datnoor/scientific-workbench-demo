# Installation Guide — Snowflake Scientific Workbench

## Quick Start

You can deploy using either a configuration file or direct CLI flags.

### Option A: Direct CLI Flags (Recommended)

```bash
# Navigate to the solution directory
cd solutions/scientific-workbench

# Deploy everything directly using your Snowflake CLI connection
bash deploy.sh --connection <your-snowflake-connection>

# Optional: Provide NVIDIA API key directly at deploy time (or set via SQL later)
bash deploy.sh --connection <your-snowflake-connection> --nvidia-key <your-nvidia-key>
```

### Option B: Config-Driven

```bash
# 1. Copy the config template and fill in your values
cp workbench.config.yaml.example workbench.config.yaml
# Edit workbench.config.yaml — optionally configure connection and secrets

# 2. Validate your configuration
bash scripts/validate-config.sh

# 3. Deploy everything
bash deploy.sh --config workbench.config.yaml
```

## Prerequisites

- Snowflake account (Enterprise edition or higher recommended)
- ACCOUNTADMIN access (for initial setup; can be reduced after)
- NVIDIA API key from [build.nvidia.com](https://build.nvidia.com) (free tier available)
- NGC API key from [ngc.nvidia.com](https://ngc.nvidia.com/setup/personal-keys) (for SPCS NIM containers)
- Snowflake CLI (`snow`) installed — [install guide](https://docs.snowflake.com/en/developer-guide/snowflake-cli/installation/installation)
- `cortex` CLI for Agent Studio agents (optional): `pip install snowflake-cli[cortex]`
- Node.js 20+ and npm (for app development)

## Step 1: Snowflake Backend Setup

Run SQL scripts in numbered order. Each is idempotent (safe to re-run).

| Step | Script | Role Required | What It Does |
|------|--------|---------------|--------------|
| 0 | `00-prerequisites.sql` | ACCOUNTADMIN | Network rules, EAI, NVIDIA API secret |
| 1 | `01-databases-and-schemas.sql` | SYSADMIN | 3 databases, all schemas |
| 2 | `02-warehouses.sql` | SYSADMIN | 3 warehouses (XS, S, M) + compute pools |
| 3 | `03-rbac.sql` | SECURITYADMIN | Roles, grants, future grants |
| 4 | `04-reference-data.sql` | SYSADMIN | Orchestrates data loading (see data/loaders/) |
| 5 | `05-tool-registry.sql` | SYSADMIN | Tool registry table, REGISTER_TOOL SP, auto-discovery task |
| 6 | `06-cortex-services.sql` | SYSADMIN | Cortex Search services (TOOL_SEARCH, ASSET_SEARCH) |
| 7 | `07-governance.sql` | SYSADMIN | Provenance log, canary assertions |
| 8 | `08-workflow-engine.sql` | SYSADMIN | Template engine + 4 workflow templates |
| 9 | `09-spcs-app-service.sql` | SYSADMIN | SPCS container service (legacy path) |
| 10 | `10-nim-spcs-services.sql` | SYSADMIN | (Optional) Deploy NVIDIA NIMs on SPCS GPUs |
| 11 | `11-validation-tests.sql` | SYSADMIN | Validation test suite SP |
| 12 | `12-tool-knowledge.sql` | SYSADMIN | Tool knowledge base for agents |
| 13 | `13-execute-tool-by-name.sql` | SYSADMIN | Agent-to-tool dispatcher procedure |
| 14 | `14-tools.sql` | SYSADMIN | Deploy all tool procedures (manifest) |
| 15 | `15-semantic-views.sql` | SYSADMIN | 4 Cortex Analyst semantic views (manifest) |
| 16 | `16-agents.sql` | SYSADMIN/ACCOUNTADMIN | Domain, orchestrator and workflow Cortex Agents + evaluation framework |
| 17 | `17-agent-studio.sh` | SYSADMIN/ACCOUNTADMIN | 4 Agent Studio YAML agents + 7 skills |
| 18 | `18-run-tests.sql` | SYSADMIN | Run all verification tests |

### Before Step 0: Configuration

1. **Copy and fill the config file:**
   ```bash
   cp workbench.config.yaml.example workbench.config.yaml
   ```

2. **Get your NVIDIA API key:**
   - Go to [build.nvidia.com](https://build.nvidia.com)
   - Create an account (free)
   - Generate an API key
   - Set `secrets.nvidia_api_key` in `workbench.config.yaml`

3. **Get your NGC API key (for SPCS NIM containers):**
   - Go to [ngc.nvidia.com/setup/personal-keys](https://ngc.nvidia.com/setup/personal-keys)
   - Generate a Personal Key with "NGC Catalog" scope
   - Set `secrets.ngc_api_key` in `workbench.config.yaml`

4. **Subscribe to CKEs (Marketplace):**
   - In Snowsight, go to Marketplace
   - Search for "PubMed" CKE — subscribe
   - Search for "ClinicalTrials.gov" CKE — subscribe
   - Set `marketplace.pubmed_cke: true` and `marketplace.clinicaltrials_cke: true`

5. **Validate configuration:**
   ```bash
   bash scripts/validate-config.sh
   ```

### Steps 14-15: Tools and Semantic Views

Scripts 14 and 15 are manifest/runner scripts. They document the files to execute
and their order. For each file listed:
- Run `tools/native/*.sql`, `tools/nvidia/*.sql`, `tools/search/*.sql` (step 14)
- Run `data/semantic_views/*.sql` (step 15)

The `deploy.sh` script handles this automatically.

### Steps 16-17: Agents

- **16-agents.sql** deploys 8 SQL-based agents (can be run directly in Snowsight)
- **17-agent-studio.sh** deploys 4 YAML agents + 7 skills (requires `cortex` CLI):
  ```bash
  bash scripts/17-agent-studio.sh --connection swb_deploy
  ```

## Step 2: React App — Local Development

```bash
# Navigate to the app directory
cd app/

# Install dependencies
npm install

# Start the dev server
npm run dev
```

The app reads Snowflake credentials from your default connection in `~/.snowflake/config.toml`.

### Snowflake Connection Configuration

Your `~/.snowflake/config.toml` should include:

```toml
[default]
account = "YOUR_ORG-YOUR_ACCOUNT"
user = "YOUR_USER"
authenticator = "OAUTH_AUTHORIZATION_CODE"
role = "WORKBENCH_SCIENTIST"
warehouse = "WORKBENCH_XS"
database = "SCIENTIFIC_WORKBENCH"
client_store_temporary_credential = true
```

Setting `client_store_temporary_credential = true` avoids repeated browser login challenges.

To use a named connection instead of default:

```bash
SNOWFLAKE_CONNECTION_NAME=myconn npm run dev
```

### First Run

1. Start `npm run dev` — the server runs on `http://localhost:3000`
2. Open the URL in your browser
3. On first API call, you'll be redirected to Snowflake for OAuth login
4. After authentication, the app loads and redirects to `/chat`

## Step 3: Deploy to Snowflake (SPCS)

### Option A: Snowflake App Runtime (Recommended)

```bash
cd app/

# Generate deployment manifest (if not already present)
snow app setup

# Deploy to Snowflake
snow app deploy
```

The app will be accessible at its `.snowflakecomputing.app` endpoint URL.

### Option B: SPCS Container Service (Manual)

1. Build the Docker image:
```bash
cd app/
docker build -t scientific-workbench-app .
```

2. Push to Snowflake image repository:
```bash
# Tag for Snowflake registry
docker tag scientific-workbench-app <repo_url>/scientific-workbench-app:latest

# Login and push
snow spcs image-registry login
docker push <repo_url>/scientific-workbench-app:latest
```

3. Create the service:
```sql
-- Run scripts/09-spcs-app-service.sql
-- This creates the SPCS service with the pushed image
```

4. Get the endpoint URL:
```sql
SHOW ENDPOINTS IN SERVICE SCIENTIFIC_WORKBENCH.CATALOG.WORKBENCH_APP_SERVICE;
```

## Verification

After installation, verify the platform:

```sql
-- Verify tools registered
SELECT COUNT(*) FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS WHERE STATUS = 'active';

-- Verify Discovery Agent invocation
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SCIENTIFIC_WORKBENCH.CATALOG.DISCOVERY_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What tools are available in the workbench?"}]}]}',
  TRUE
);
-- Expected: 23

-- Verify workflow templates
SELECT COUNT(*) FROM SCIENTIFIC_WORKBENCH.WORKFLOWS.TEMPLATES WHERE STATUS = 'active';
-- Expected: 4

-- Verify governance objects
SELECT COUNT(*) FROM SCIENTIFIC_WORKBENCH.GOVERNANCE.CANARY_ASSERTIONS WHERE ACTIVE = TRUE;
-- Expected: 20

-- Verify provenance logging
SELECT COUNT(*) FROM SCIENTIFIC_WORKBENCH.PROVENANCE.PROVENANCE_LOG;
-- Should be > 0 after running any workflow

-- Run validation test suite
-- scripts/11-validation-tests.sql
```

## Teardown

To completely remove the Scientific Workbench from an account:

```bash
# Full teardown (drops ALL objects — irreversible)
bash teardown.sh --connection <your-connection>

# Preview what would be dropped without executing
bash teardown.sh --dry-run --connection <your-connection>

# Keep reference and project data, remove everything else
bash teardown.sh --keep-data --connection <your-connection>

# Skip the confirmation prompt
bash teardown.sh --connection <your-connection> -y
```

The teardown script drops objects in dependency order: tasks → SAR app → SPCS services → agents → integrations → network rules → secrets → compute pools → databases (cascades tables, procedures, stages, views) → warehouses → roles.

**Warning**: This is irreversible. All data, tool results, agent configurations, and workflow history will be permanently deleted. Use `--keep-data` to preserve `WORKBENCH_REFERENCE` and `WORKBENCH_PROJECTS` databases.

## Estimated Resources

| Resource | Size |
|----------|------|
| Storage (reference data) | ~40 GB |
| Storage (platform tables) | < 1 GB |
| Warehouses | 3 (XS, S, M) — auto-suspend |
| Cortex Search | 2 services (catalog + tools) |
| CKEs | 2 (PubMed + Trials) — Marketplace |
| GPU | 0 (NVIDIA API handles compute) |
| Monthly credits (estimate) | 500-1,000 |

## Troubleshooting

### Authentication Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Repeated browser login prompts | Credentials not cached | Set `client_store_temporary_credential = true` in `~/.snowflake/config.toml` |
| "OAuth token expired" errors | Stale cached token | Delete `~/.snowflake/session/` directory and re-authenticate |
| 401 on API calls after deploy | Missing caller's rights grants | Run `GRANT USAGE ON SERVICE ... TO ROLE WORKBENCH_SCIENTIST` |

### App Runtime Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| 404 on all pages after deploy | Turbopack re-rooted to parent dir | Ensure no `package-lock.json` exists in any parent directory of `app/`. The `next.config.mjs` pins `turbopack.root` to prevent this. |
| Static chunks return 404 | Using standalone server locally | Use `npm run dev` or `npm run start`, NOT `node .next/standalone/server.js` for local preview |
| Pages show "Loading..." forever | Client hydration failed | Check browser console for errors. Usually a JS chunk 404 (see above) |
| `snow app deploy` fails | Missing `snowflake.yml` | Run `snow app setup` first to generate the deployment manifest |

### Data & Query Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| NVIDIA API calls fail | Missing EAI or secret | `SHOW EXTERNAL ACCESS INTEGRATIONS;` — verify `NVIDIA_API_EAI` exists |
| Tool not found by agent | Cortex Search service down | `SHOW CORTEX SEARCH SERVICES IN SCHEMA SCIENTIFIC_WORKBENCH.CATALOG;` |
| Permission denied on queries | Missing role grants | `SHOW GRANTS TO ROLE WORKBENCH_SCIENTIST;` — verify grants on required schemas |
| Canary assertion failures | Reference data not loaded | Run the data loader scripts from Step 1 |
| Empty tables on Explore page | Wrong database context | Verify `SCIENTIFIC_WORKBENCH` database exists with expected schemas |
| Governance page shows no data | Provenance/promotion tables empty | Normal for fresh install — data appears after running workflows |

### Development Tips

- **Hot reload**: `npm run dev` supports hot module replacement. Edit any `.tsx` file and changes appear instantly.
- **Type checking**: Run `npx tsc --noEmit` to check for TypeScript errors without building.
- **Build test**: Run `npx next build` to verify the production build compiles cleanly before deploying.
- **Connection pooling**: The Snowflake SDK maintains a connection pool (`min: 1, max: 10`). The first query triggers OAuth; subsequent queries reuse the pool.
- **Bind variables**: All API routes use parameterized queries (`?` placeholders) for SQL injection prevention. Never concatenate user input into SQL strings.
