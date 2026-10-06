-- =============================================================================
-- data/loaders/load_gene_ontology.sql  Gene Ontology + annotations
-- data/loaders/load_reactome.sql       Reactome pathways
-- data/loaders/load_msigdb.sql         MSigDB Hallmarks + C2:CP
-- data/loaders/load_uniprot.sql        UniProt Swiss-Prot
-- data/loaders/load_clinicaltrials.sql ClinicalTrials.gov
-- =============================================================================

-- ==========================================================================
-- GENE ONTOLOGY
-- ==========================================================================
USE DATABASE WORKBENCH_REFERENCE; USE SCHEMA PATHWAYS;

CREATE TABLE IF NOT EXISTS PATHWAYS.GO_TERMS (
    go_id           VARCHAR NOT NULL,  -- GO:0000001
    term_name       VARCHAR,
    namespace       VARCHAR,           -- biological_process | molecular_function | cellular_component
    definition      VARCHAR,
    is_obsolete     BOOLEAN DEFAULT FALSE
) COMMENT = 'Gene Ontology terms';

CREATE TABLE IF NOT EXISTS PATHWAYS.GO_ANNOTATIONS (
    db_object_symbol VARCHAR,  -- gene symbol
    go_id           VARCHAR,
    qualifier       VARCHAR,
    aspect          VARCHAR,  -- P | F | C
    taxon_id        VARCHAR,
    assigned_by     VARCHAR
) COMMENT = 'GO gene annotations (human, GAF format)';

-- ==========================================================================
-- REACTOME
-- ==========================================================================
CREATE TABLE IF NOT EXISTS PATHWAYS.PATHWAYS (
    pathway_id      VARCHAR NOT NULL,
    pathway_name    VARCHAR,
    species         VARCHAR,
    level           VARCHAR  -- top-level | pathway | reaction
) COMMENT = 'Reactome pathways';

CREATE TABLE IF NOT EXISTS PATHWAYS.PATHWAY_GENES (
    pathway_id      VARCHAR,
    gene_symbol     VARCHAR,
    uniprot_id      VARCHAR
) COMMENT = 'Reactome pathway-gene mapping';

-- ==========================================================================
-- MSIGDB
-- ==========================================================================
CREATE TABLE IF NOT EXISTS PATHWAYS.GENE_SETS (
    gene_set_id     NUMBER AUTOINCREMENT,
    gene_set_name   VARCHAR NOT NULL,
    collection      VARCHAR,   -- HALLMARKS | C2_CP | C6 | etc.
    description     VARCHAR,
    source_url      VARCHAR
) COMMENT = 'MSigDB gene set definitions';

CREATE TABLE IF NOT EXISTS PATHWAYS.GENE_SET_MEMBERS (
    gene_set_id     NUMBER,
    gene_symbol     VARCHAR
) COMMENT = 'MSigDB gene-to-gene-set mapping';

-- ==========================================================================
-- UNIPROT (Swiss-Prot)
-- ==========================================================================
USE SCHEMA PROTEIN;

CREATE TABLE IF NOT EXISTS PROTEIN.UNIPROT_ENTRIES (
    uniprot_id      VARCHAR NOT NULL,   -- P12345
    gene_name       VARCHAR,
    protein_name    VARCHAR,
    organism        VARCHAR,
    tax_id          NUMBER,
    sequence        VARCHAR,            -- amino acid sequence
    length          INT,
    mass            INT,
    function_desc   VARCHAR,
    subcell_location VARCHAR,
    ec_number       VARCHAR,
    loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'UniProt Swiss-Prot reviewed protein entries';

-- ==========================================================================
-- CLINICALTRIALS.GOV
-- ==========================================================================
USE DATABASE WORKBENCH_REFERENCE; USE SCHEMA CLINICAL;

CREATE TABLE IF NOT EXISTS CLINICAL.STUDIES (
    nct_id          VARCHAR NOT NULL,
    official_title  VARCHAR,
    brief_title     VARCHAR,
    overall_status  VARCHAR,
    phase           VARCHAR,
    start_date      DATE,
    completion_date DATE,
    primary_purpose VARCHAR,
    sponsor         VARCHAR,
    funding_source  VARCHAR
) COMMENT = 'ClinicalTrials.gov study registry';

CREATE TABLE IF NOT EXISTS CLINICAL.CONDITIONS (
    nct_id          VARCHAR,
    condition_name  VARCHAR,
    condition_mesh  VARCHAR
) COMMENT = 'Trial conditions (indications)';

CREATE TABLE IF NOT EXISTS CLINICAL.INTERVENTIONS (
    nct_id          VARCHAR,
    intervention_type VARCHAR,
    intervention_name VARCHAR,
    other_names     VARCHAR
) COMMENT = 'Trial interventions (drugs, biologics, procedures)';

-- Refresh tasks
CREATE OR REPLACE TASK CLINICAL.TASK_REFRESH_TRIALS
  WAREHOUSE = WORKBENCH_ML
  SCHEDULE = 'USING CRON 0 4 * * 0 UTC'  -- Weekly on Sunday 04:00 UTC
  COMMENT = 'Weekly ClinicalTrials.gov refresh'
AS SELECT CURRENT_TIMESTAMP();  -- Placeholder

-- Verification
SELECT 'GO_TERMS' AS tbl, COUNT(*) AS row_count FROM WORKBENCH_REFERENCE.PATHWAYS.GO_TERMS
UNION ALL SELECT 'REACTOME_PATHWAYS', COUNT(*) FROM WORKBENCH_REFERENCE.PATHWAYS.PATHWAYS
UNION ALL SELECT 'GENE_SETS', COUNT(*) FROM WORKBENCH_REFERENCE.PATHWAYS.GENE_SETS
UNION ALL SELECT 'GENE_SET_MEMBERS', COUNT(*) FROM WORKBENCH_REFERENCE.PATHWAYS.GENE_SET_MEMBERS
UNION ALL SELECT 'UNIPROT', COUNT(*) FROM WORKBENCH_REFERENCE.PROTEIN.UNIPROT_ENTRIES
UNION ALL SELECT 'TRIALS', COUNT(*) FROM WORKBENCH_REFERENCE.CLINICAL.STUDIES;
