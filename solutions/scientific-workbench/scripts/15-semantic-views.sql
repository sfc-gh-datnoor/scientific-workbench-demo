-- =============================================================================
-- 15-semantic-views.sql
-- Deploy Cortex Analyst semantic views for natural-language data querying.
-- Run as SYSADMIN with warehouse WORKBENCH_XS
--
-- Prerequisites:
--   - Reference data loaded (Phase 2: data/loaders/*.sql)
--   - Synthetic demo data loaded (data/synthetic/load_synthetic_data.sql)
--   - These semantic views read from tables in WORKBENCH_REFERENCE and
--     WORKBENCH_PROJECTS that must be populated first.
-- =============================================================================

USE ROLE SYSADMIN;
USE DATABASE SCIENTIFIC_WORKBENCH;
USE WAREHOUSE WORKBENCH_XS;

-- =============================================================================
-- SEMANTIC VIEWS
-- =============================================================================
-- Each file creates a semantic view in SCIENTIFIC_WORKBENCH.CATALOG that
-- enables Cortex Analyst text-to-SQL over the underlying tables.
-- Execute each file in order.
--
-- File: data/semantic_views/sv_chemistry.sql
--   Creates: CATALOG.SV_CHEMISTRY
--   Tables:  WORKBENCH_REFERENCE.CHEMBL.MOLECULE_DICTIONARY + related
--   Purpose: Natural language queries over ChEMBL chemical reference data
--
-- File: data/semantic_views/sv_clinical.sql
--   Creates: CATALOG.SV_CLINICAL
--   Tables:  WORKBENCH_PROJECTS.DEMO_NSCLC.PATIENTS + related
--   Purpose: Natural language queries over clinical / patient outcome data
--
-- File: data/semantic_views/sv_compounds.sql
--   Creates: CATALOG.SV_COMPOUNDS
--   Tables:  WORKBENCH_PROJECTS.DEMO_COMPOUNDS.COMPOUNDS + related
--   Purpose: Natural language queries over compound IC50 / assay project data
--
-- File: data/semantic_views/sv_genomics.sql
--   Creates: CATALOG.SV_GENOMICS
--   Tables:  WORKBENCH_PROJECTS.DEMO_NSCLC.GENE_EXPRESSION + related
--   Purpose: Natural language queries over gene expression + pathway data

-- =============================================================================
-- VERIFICATION
-- =============================================================================
-- After running all 4 semantic view files, confirm they exist:

SELECT 'Semantic Views' AS check_name,
       COUNT(*)         AS view_count,
       CASE WHEN COUNT(*) >= 4 THEN 'PASS' ELSE 'FAIL — expected >= 4' END AS status
FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'CATALOG'
  AND TABLE_NAME LIKE 'SV_%';
