-- =============================================================================
-- 18-run-tests.sql
-- Run the full verification suite: individual test files + RUN_VALIDATION_TESTS
-- Run as WORKBENCH_ADMIN (or SYSADMIN) with warehouse WORKBENCH_XS
--
-- This is a manifest/runner script. Execute the test files listed below in
-- order, then run the comprehensive validation procedure.
--
-- Prerequisites: ALL previous setup scripts (00-17) and data loading complete.
-- =============================================================================

USE ROLE SYSADMIN;
USE DATABASE SCIENTIFIC_WORKBENCH;
USE WAREHOUSE WORKBENCH_XS;

-- =============================================================================
-- TEST FILES (execute each in order)
-- =============================================================================
--
-- File: tests/canary_test.sql
--   Verifies: Canary assertions are seeded, governance tasks running
--
-- File: tests/tool_registry_test.sql
--   Verifies: All 21+ tools are registered and discoverable via TOOL_SEARCH
--
-- File: tests/nim_smoke_test.sql
--   Verifies: Each NIM tool can call the hosted API and parse a result
--   Note: Requires NVIDIA_API_SECRET to be set with a valid key
--
-- File: tests/workflow_test.sql
--   Verifies: WF1 (Hit Generation & Scoring) workflow template runs end-to-end
--   Note: Requires NVIDIA API key + reference data loaded

-- =============================================================================
-- COMPREHENSIVE VALIDATION
-- =============================================================================
-- After running the individual test files above, run the comprehensive
-- validation procedure that checks all infrastructure components:

CALL SCIENTIFIC_WORKBENCH.CATALOG.RUN_VALIDATION_TESTS();
