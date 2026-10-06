-- =============================================================================
-- 06-cortex-services.sql
-- Cortex Agent, Cortex Search services, and Semantic Views
-- Run as SYSADMIN
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;
USE WAREHOUSE WORKBENCH_XS;

-- =============================================================================
-- 1. CORTEX SEARCH SERVICES
-- =============================================================================

-- Asset Catalog Search (datasets, tools, experiments)
CREATE OR REPLACE CORTEX SEARCH SERVICE CATALOG.ASSET_SEARCH
  ON asset_name
  ATTRIBUTES description, asset_type, domain, schema_name, owner
  WAREHOUSE = WORKBENCH_XS
  TARGET_LAG = '1 hour'
  AS (
    SELECT
      asset_id,
      asset_name,
      description,
      asset_type,
      domain,
      schema_name,
      owner,
      created_at
    FROM SCIENTIFIC_WORKBENCH.CATALOG.ASSETS
  )
  ;

-- Tool Search (agent discovers tools by intent)
CREATE OR REPLACE CORTEX SEARCH SERVICE CATALOG.TOOL_SEARCH
  ON description
  ATTRIBUTES display_name, domain, parameters, example_usage, tool_type
  WAREHOUSE = WORKBENCH_XS
  TARGET_LAG = '1 hour'
  AS (
    SELECT
      tool_id,
      display_name,
      description,
      domain::VARCHAR AS domain,
      parameters,
      example_usage,
      function_reference,
      tool_type
    FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
    WHERE status = 'active'
  )
  ;

-- Re-granted on every run: CREATE OR REPLACE above drops existing grants.
GRANT USAGE ON CORTEX SEARCH SERVICE CATALOG.TOOL_SEARCH TO ROLE WORKBENCH_ADMIN;
GRANT USAGE ON CORTEX SEARCH SERVICE CATALOG.ASSET_SEARCH TO ROLE WORKBENCH_ADMIN;
GRANT USAGE ON CORTEX SEARCH SERVICE CATALOG.TOOL_SEARCH TO ROLE WORKBENCH_SCIENTIST;
GRANT USAGE ON CORTEX SEARCH SERVICE CATALOG.ASSET_SEARCH TO ROLE WORKBENCH_SCIENTIST;

-- =============================================================================
-- 2. CKE SUBSCRIPTIONS (from Marketplace)
-- =============================================================================
-- PubMed and ClinicalTrials.gov are available as Cortex Knowledge Extensions
-- Subscribe via Snowflake Marketplace:
--   - Search Marketplace for "PubMed" CKE
--   - Search Marketplace for "ClinicalTrials" CKE
-- After subscription, they are available as agent tools automatically.

-- =============================================================================
-- 3. CORTEX AGENT
-- =============================================================================
-- DISCOVERY_AGENT is created in Phase 5 by engine/sql/create_workflow_runner.sql
-- with the full YAML specification. Not created here to avoid overwriting.
-- =============================================================================

-- =============================================================================
-- 4. SEMANTIC VIEWS (Cortex Analyst)
-- =============================================================================
-- See data/semantic_views/ for full DDL:
--   - sv_chemistry.sql (compounds, activities, targets)
--   - sv_genomics.sql (genes, expression, pathways)
--   - sv_clinical.sql (patients, outcomes, trials)
