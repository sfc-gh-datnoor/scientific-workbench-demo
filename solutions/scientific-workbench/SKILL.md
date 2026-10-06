---
name: scientific-workbench
description: >
  Install or teardown the Snowflake Scientific Workbench solution for Life Sciences R&D.
  Usage: $sf-hcls-solutions:scientific-workbench | $sf-hcls-solutions:scientific-workbench teardown
  Triggers: scientific workbench, drug discovery, genomics, chemistry, bio, nims, boltz2, genmol, rfdiffusion, diffdock, proteinmpnn, life sciences.
tools:
  - snowflake_sql_execute
  - snowflake_object_search
  - Bash
  - Read
  - Glob
  - Grep
  - WebFetch
---

# Snowflake Scientific Workbench

Parse the action from `$ARGUMENTS`:
- If `$ARGUMENTS` is "install" or empty → run **Install** flow
- If `$ARGUMENTS` is "teardown" → run **Teardown** flow
- Otherwise → show usage help

## Overview

- **Industry:** Healthcare & Life Sciences
- **Database:** `SCIENTIFIC_WORKBENCH`, `WORKBENCH_REFERENCE`, `WORKBENCH_PROJECTS`, `SNOWFLAKE_APPS`
- **Schemas:** `CATALOG`, `WORKFLOWS`, `PROVENANCE`, `GOVERNANCE`, `RESULTS`
- **Features:** Cortex Agents, Cortex Analyst, NVIDIA BioNeMo NIMs, Snowpark Tools, Snowflake App Runtime, Notebooks
- **Role Required:** `ACCOUNTADMIN`
- **Prerequisites:** NVIDIA API key from [build.nvidia.com](https://build.nvidia.com) (free tier supported)

## Install Flow

1. **Locate Solution Directory:**
   Navigate to `solutions/scientific-workbench/` in `sf-hcls-solutions`.

2. **Run Master Setup Script:**
   Execute `scripts/setup.sql` or use `deploy.sh`:
   ```bash
   bash deploy.sh --connection <your-connection>
   ```

3. **Configure NVIDIA API Key:**
   ```sql
   ALTER SECRET SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET SET SECRET_STRING = '<your-nvidia-api-key>';
   ```

4. **Verify Deployment:**
   ```sql
   -- Verify 23 active scientific tools
   SELECT COUNT(*) FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS WHERE STATUS = 'active';

   -- Verify Discovery Agent
   SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
     'SCIENTIFIC_WORKBENCH.CATALOG.DISCOVERY_AGENT',
     '{"messages":[{"role":"user","content":[{"type":"text","text":"What tools are available in the workbench?"}]}]}',
     TRUE
   );
   ```

## Teardown Flow

To drop all workbench objects in reverse dependency order:
```bash
bash teardown.sh --connection <your-connection> -y
```
Or execute `scripts/teardown.sql` with `ACCOUNTADMIN`.
