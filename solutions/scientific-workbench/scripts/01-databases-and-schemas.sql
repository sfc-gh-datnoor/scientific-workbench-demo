-- =============================================================================
-- 01-databases-and-schemas.sql
-- Database and schema structure for the Scientific Workbench
-- Run as SYSADMIN
-- =============================================================================

-- Platform database (workbench infrastructure)
CREATE DATABASE IF NOT EXISTS SCIENTIFIC_WORKBENCH
  COMMENT = 'Snowflake Scientific Workbench — platform infrastructure';

USE DATABASE SCIENTIFIC_WORKBENCH;

-- Core platform schemas
CREATE SCHEMA IF NOT EXISTS CATALOG
  COMMENT = 'Asset catalog, tool registry, search services';

CREATE SCHEMA IF NOT EXISTS GOVERNANCE
  COMMENT = 'Audit trail, canary assertions, data quality';

CREATE SCHEMA IF NOT EXISTS PROVENANCE
  COMMENT = 'Immutable provenance log for all actions';

CREATE SCHEMA IF NOT EXISTS RESULTS
  COMMENT = 'Agent and tool execution outputs';

CREATE SCHEMA IF NOT EXISTS WORKFLOWS
  COMMENT = 'Template+Agent workflow engine';

-- Reference data database (shared read-only)
CREATE DATABASE IF NOT EXISTS WORKBENCH_REFERENCE
  COMMENT = 'Public reference datasets for life sciences R&D';

USE DATABASE WORKBENCH_REFERENCE;

CREATE SCHEMA IF NOT EXISTS CHEMBL
  COMMENT = 'ChEMBL — compounds, targets, activities (~30GB)';

CREATE SCHEMA IF NOT EXISTS PROTEIN
  COMMENT = 'UniProt Swiss-Prot — protein sequences and annotations (~5GB)';

CREATE SCHEMA IF NOT EXISTS PATHWAYS
  COMMENT = 'Gene Ontology, Reactome, MSigDB — pathways and gene sets';

CREATE SCHEMA IF NOT EXISTS GENOMICS
  COMMENT = 'HGNC gene nomenclature, GTEx expression';

CREATE SCHEMA IF NOT EXISTS CLINICAL
  COMMENT = 'ClinicalTrials.gov structured data';

CREATE SCHEMA IF NOT EXISTS DRUGS
  COMMENT = 'DrugBank — drug information and targets';

-- Customer projects database (per-project isolation)
CREATE DATABASE IF NOT EXISTS WORKBENCH_PROJECTS
  COMMENT = 'Customer project data — one schema per project';

USE DATABASE WORKBENCH_PROJECTS;

CREATE SCHEMA IF NOT EXISTS DEMO_NSCLC
  COMMENT = 'Demo project: KRAS G12C resistance in NSCLC';

CREATE SCHEMA IF NOT EXISTS SHARED_ANALYTICS
  COMMENT = 'Cross-project analytics views';
