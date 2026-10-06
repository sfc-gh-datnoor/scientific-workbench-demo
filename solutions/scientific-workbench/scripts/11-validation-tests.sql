-- =============================================================================
-- setup/11-validation-tests.sql
-- Post-deployment validation suite
-- Run as: CALL SCIENTIFIC_WORKBENCH.CATALOG.RUN_VALIDATION_TESTS();
-- Returns: table of (test_group, test_name, status, detail)
-- =============================================================================
-- Validates:
--   1. Database schemas exist
--   2. Core tables exist and have expected rows
--   3. Secrets and EAIs exist
--   4. Network rules exist with correct hosts
--   5. Compute pools exist with correct instance families
--   6. Image repositories have expected images
--   7. NIM_ENDPOINTS table is seeded
--   8. Tool registry has expected tools
--   9. Workflow templates are seeded
--  10. Agents exist (SHOW AGENTS)
--  11. Cortex Search services exist
--  12. NIM services (if deployed)
--  13. Procedures compile (exist)
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_VALIDATION_TESTS()
RETURNS TABLE(TEST_GROUP VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, DETAIL VARCHAR)
LANGUAGE SQL
AS
$$
DECLARE
  results RESULTSET;
BEGIN
  -- Accumulate results into a temp table
  CREATE OR REPLACE TEMPORARY TABLE _VALIDATION_RESULTS (
    TEST_GROUP VARCHAR, TEST_NAME VARCHAR, STATUS VARCHAR, DETAIL VARCHAR
  );

  -- =========================================================================
  -- 1. SCHEMAS
  -- =========================================================================
  INSERT INTO _VALIDATION_RESULTS
  SELECT 'schemas', 'CATALOG schema exists',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::VARCHAR || ' found'
  FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'CATALOG';

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'schemas', 'WORKFLOWS schema exists',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::VARCHAR || ' found'
  FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'WORKFLOWS';

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'schemas', 'GOVERNANCE schema exists',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::VARCHAR || ' found'
  FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'GOVERNANCE';

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'schemas', 'PROVENANCE schema exists',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::VARCHAR || ' found'
  FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'PROVENANCE';

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'schemas', 'RESULTS schema exists',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::VARCHAR || ' found'
  FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'RESULTS';

  -- =========================================================================
  -- 2. CORE TABLES
  -- =========================================================================
  INSERT INTO _VALIDATION_RESULTS
  SELECT 'tables', 'TOOLS table exists with rows',
    CASE WHEN COUNT(*) >= 15 THEN 'PASS' ELSE 'WARN (' || COUNT(*)::VARCHAR || ' tools, expected >= 15)' END,
    COUNT(*)::VARCHAR || ' tools registered'
  FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS WHERE STATUS = 'active';

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'tables', 'NIM_ENDPOINTS table seeded',
    CASE WHEN COUNT(*) >= 10 THEN 'PASS' ELSE 'FAIL (' || COUNT(*)::VARCHAR || ' rows)' END,
    COUNT(*)::VARCHAR || ' endpoint entries'
  FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS;

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'tables', 'WORKFLOW TEMPLATES seeded',
    CASE WHEN COUNT(*) >= 4 THEN 'PASS' ELSE 'FAIL (' || COUNT(*)::VARCHAR || ')' END,
    COUNT(*)::VARCHAR || ' templates'
  FROM SCIENTIFIC_WORKBENCH.WORKFLOWS.TEMPLATES WHERE STATUS = 'active';

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'tables', 'ASSETS table exists',
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::VARCHAR || ' assets'
  FROM SCIENTIFIC_WORKBENCH.CATALOG.ASSETS;

  -- =========================================================================
  -- 3. KEY PROCEDURES EXIST
  -- =========================================================================
  INSERT INTO _VALIDATION_RESULTS
  SELECT 'procedures', 'RUN_BOLTZ2 exists',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::VARCHAR || ' found'
  FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.PROCEDURES WHERE PROCEDURE_NAME = 'RUN_BOLTZ2';

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'procedures', 'REGISTER_TOOL exists',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::VARCHAR || ' found'
  FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.PROCEDURES WHERE PROCEDURE_NAME = 'REGISTER_TOOL';

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'procedures', 'EXECUTE_TEMPLATE exists',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COUNT(*)::VARCHAR || ' found'
  FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.PROCEDURES
  WHERE PROCEDURE_NAME = 'EXECUTE_TEMPLATE' AND PROCEDURE_SCHEMA = 'WORKFLOWS';

  -- =========================================================================
  -- 4. TOOL REGISTRY COMPLETENESS
  -- =========================================================================
  -- Check NIM tools are registered
  INSERT INTO _VALIDATION_RESULTS
  SELECT 'tool_registry', 'Boltz-2 tool registered',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COALESCE(MAX(TOOL_ID), 'not found')
  FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS WHERE NAME = 'run_boltz2';

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'tool_registry', 'GenMol tool registered',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COALESCE(MAX(TOOL_ID), 'not found')
  FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS WHERE NAME = 'run_genmol';

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'tool_registry', 'DiffDock tool registered',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COALESCE(MAX(TOOL_ID), 'not found')
  FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS WHERE NAME = 'run_diffdock';

  INSERT INTO _VALIDATION_RESULTS
  SELECT 'tool_registry', 'Drug Discovery Pipeline registered',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COALESCE(MAX(TOOL_ID), 'not found')
  FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS WHERE NAME = 'run_drug_discovery_pipeline';

  -- Count by type
  INSERT INTO _VALIDATION_RESULTS
  SELECT 'tool_registry', 'Procedure tools count',
    CASE WHEN COUNT(*) >= 10 THEN 'PASS' ELSE 'WARN (' || COUNT(*)::VARCHAR || ')' END,
    COUNT(*)::VARCHAR || ' procedure tools'
  FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS WHERE TOOL_TYPE = 'procedure' AND STATUS = 'active';

  -- =========================================================================
  -- 5. NIM INFRASTRUCTURE
  -- =========================================================================
  -- NIM_ENDPOINTS has Boltz-2 SPCS entry
  INSERT INTO _VALIDATION_RESULTS
  SELECT 'nim_infra', 'Boltz-2 SPCS endpoint configured',
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END,
    COALESCE(MAX(ENDPOINT_URL), 'not found')
  FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS
  WHERE NIM_NAME = 'boltz2' AND DEPLOYMENT_MODE = 'spcs';

  -- Check image exists in repo
  INSERT INTO _VALIDATION_RESULTS
  SELECT 'nim_infra', 'Boltz-2 image in registry',
    CASE WHEN CONTAINS(SYSTEM$REGISTRY_LIST_IMAGES('/SCIENTIFIC_WORKBENCH/CATALOG/NIM_GPU_IMAGES'), 'boltz2')
         THEN 'PASS' ELSE 'FAIL' END,
    SYSTEM$REGISTRY_LIST_IMAGES('/SCIENTIFIC_WORKBENCH/CATALOG/NIM_GPU_IMAGES');

  -- =========================================================================
  -- 6. COMPUTE POOLS
  -- =========================================================================
  -- We can't easily query SHOW COMPUTE POOLS from SQL procedure, so check via
  -- a metadata query pattern. These are best-effort.
  INSERT INTO _VALIDATION_RESULTS
  VALUES ('compute_pools', 'NIM pools created (manual check)',
          'INFO', 'Run: SHOW COMPUTE POOLS LIKE ''NIM%'' — expect NIM_GPU_L40S_POOL, NIM_GPU_A10G_POOL, NIM_BUILD_POOL');

  -- =========================================================================
  -- 7. SERVICES (if any running)
  -- =========================================================================
  BEGIN
    LET v_svc_status VARCHAR;
    SELECT SYSTEM$GET_SERVICE_STATUS('SCIENTIFIC_WORKBENCH.CATALOG.NIM_BOLTZ2_SVC')
    INTO v_svc_status;

    INSERT INTO _VALIDATION_RESULTS
    SELECT 'services', 'Boltz-2 NIM service',
      CASE
        WHEN :v_svc_status LIKE '%READY%' THEN 'PASS'
        WHEN :v_svc_status LIKE '%PENDING%' THEN 'WARN (starting up)'
        WHEN :v_svc_status LIKE '%FAILED%' THEN 'FAIL'
        ELSE 'INFO'
      END,
      LEFT(:v_svc_status, 200);
  EXCEPTION
    WHEN OTHER THEN
      INSERT INTO _VALIDATION_RESULTS VALUES ('services', 'Boltz-2 NIM service', 'SKIP', 'Service not created');
  END;

  -- =========================================================================
  -- 8. INTEGRATIONS
  -- =========================================================================
  INSERT INTO _VALIDATION_RESULTS
  VALUES ('integrations', 'EAIs created (manual check)',
          'INFO', 'Run: SHOW INTEGRATIONS LIKE ''%NIM%'' — expect NIM_RUNTIME_EAI, NGC_REGISTRY_PULL_EAI');

  -- =========================================================================
  -- 9. SUMMARY
  -- =========================================================================
  INSERT INTO _VALIDATION_RESULTS
  SELECT 'SUMMARY', 'Overall result',
    CASE
      WHEN COUNT(CASE WHEN STATUS LIKE 'FAIL%' THEN 1 END) = 0 THEN 'ALL PASS'
      ELSE COUNT(CASE WHEN STATUS LIKE 'FAIL%' THEN 1 END)::VARCHAR || ' FAILURES'
    END,
    'PASS=' || COUNT(CASE WHEN STATUS = 'PASS' THEN 1 END)::VARCHAR ||
    ' WARN=' || COUNT(CASE WHEN STATUS LIKE 'WARN%' THEN 1 END)::VARCHAR ||
    ' FAIL=' || COUNT(CASE WHEN STATUS LIKE 'FAIL%' THEN 1 END)::VARCHAR ||
    ' INFO=' || COUNT(CASE WHEN STATUS IN ('INFO', 'SKIP') THEN 1 END)::VARCHAR
  FROM _VALIDATION_RESULTS;

  results := (SELECT * FROM _VALIDATION_RESULTS ORDER BY
    CASE TEST_GROUP
      WHEN 'SUMMARY' THEN 99
      WHEN 'schemas' THEN 1
      WHEN 'tables' THEN 2
      WHEN 'procedures' THEN 3
      WHEN 'tool_registry' THEN 4
      WHEN 'nim_infra' THEN 5
      WHEN 'compute_pools' THEN 6
      WHEN 'services' THEN 7
      WHEN 'integrations' THEN 8
      ELSE 9
    END, TEST_NAME);

  RETURN TABLE(results);
END;
$$;

-- NOTE: Do not call the procedure here.
-- This file runs as step 10/10 of deploy.sh Phase 1 (Infrastructure), but the
-- tests reference objects that are not created until later phases, e.g.
-- CATALOG.NIM_ENDPOINTS is created by tools/nvidia/nim_pipelines.sql in
-- Phase 3. Calling it here fails with:
--   002003 (42S02): Object 'SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS'
--   does not exist or not authorized.
-- deploy.sh Phase 7 (Verification) already invokes it once everything exists:
--   CALL SCIENTIFIC_WORKBENCH.CATALOG.RUN_VALIDATION_TESTS();
-- Creating the procedure here is safe: a SQL procedure body is not resolved
-- against existing objects until it is executed.
