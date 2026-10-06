-- =============================================================================
-- data/loaders/load_hgnc.sql
-- Load HGNC gene nomenclature into WORKBENCH_REFERENCE.GENOMICS
-- Source: https://www.genenames.org/download/archive/
-- File: hgnc_complete_set.txt (tab-delimited, ~50MB)
-- =============================================================================

USE DATABASE WORKBENCH_REFERENCE;
USE SCHEMA GENOMICS;
USE WAREHOUSE WORKBENCH_ML;

-- Stage for HGNC download
CREATE STAGE IF NOT EXISTS GENOMICS.HGNC_STAGE
  FILE_FORMAT = (TYPE = 'CSV' FIELD_DELIMITER = '\t' SKIP_HEADER = 1
                 NULL_IF = ('', '\"\"') FIELD_OPTIONALLY_ENCLOSED_BY = '"')
  COMMENT = 'HGNC complete gene set download';

CREATE TABLE IF NOT EXISTS GENOMICS.HGNC_GENES (
    hgnc_id          VARCHAR,
    approved_symbol  VARCHAR,
    approved_name    VARCHAR,
    status           VARCHAR,    -- Approved | Entry Withdrawn
    locus_type       VARCHAR,    -- protein-coding gene, RNA, pseudogene, etc.
    locus_group      VARCHAR,
    prev_symbols     VARCHAR,    -- pipe-delimited list
    alias_symbols    VARCHAR,    -- pipe-delimited list
    chromosome       VARCHAR,
    location         VARCHAR,
    location_sortable VARCHAR,
    entrez_id        VARCHAR,
    ensembl_id       VARCHAR,
    ucsc_id          VARCHAR,
    refseq_id        VARCHAR,
    uniprot_id       VARCHAR,
    omim_id          VARCHAR,
    loaded_at        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'HGNC approved human gene nomenclature — monthly refresh';

-- After uploading hgnc_complete_set.txt to @HGNC_STAGE:
-- COPY INTO GENOMICS.HGNC_GENES (
--     hgnc_id, approved_symbol, approved_name, status, locus_type, locus_group,
--     prev_symbols, alias_symbols, chromosome, location, location_sortable,
--     entrez_id, ensembl_id, ucsc_id, refseq_id, uniprot_id, omim_id
-- )
-- FROM @HGNC_STAGE/hgnc_complete_set.txt
-- ON_ERROR = CONTINUE;

-- Refresh task (monthly)
CREATE OR REPLACE TASK GENOMICS.TASK_REFRESH_HGNC
  WAREHOUSE = WORKBENCH_ML
  SCHEDULE = 'USING CRON 0 2 1 * * UTC'  -- 1st of each month at 02:00 UTC
  COMMENT = 'Monthly HGNC refresh'
AS
  -- Refresh logic: truncate + reload from stage.
  -- The TRUNCATE below both defines the task body and terminates the
  -- CREATE TASK statement. A second bare ';' after the trailing comment
  -- used to follow, which the deploy script's comment stripping reduced to
  -- an empty statement, failing with:
  --   000900 (42601): SQL compilation error: Empty SQL statement.
  -- (COPY INTO statement runs after file is re-staged.)
  TRUNCATE TABLE IF EXISTS GENOMICS.HGNC_GENES;

-- Verification
SELECT 'HGNC' AS table_name, COUNT(*) AS row_count
FROM GENOMICS.HGNC_GENES
WHERE status = 'Approved';
