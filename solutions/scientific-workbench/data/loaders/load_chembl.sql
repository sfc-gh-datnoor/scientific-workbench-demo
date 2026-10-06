-- =============================================================================
-- data/loaders/load_chembl.sql
-- Load ChEMBL 35 into WORKBENCH_REFERENCE.CHEMBL (~30GB)
-- Source: https://chembl.gitbook.io/chembl-interface-documentation/downloads
-- Files: chembl_35_postgresql.dmp or chembl_35.sdf / chembl_35_*.tsv
-- =============================================================================

USE DATABASE WORKBENCH_REFERENCE;
USE SCHEMA CHEMBL;
USE WAREHOUSE WORKBENCH_ML;

-- Compound structures (core table)
CREATE TABLE IF NOT EXISTS CHEMBL.MOLECULE_DICTIONARY (
    chembl_id       VARCHAR NOT NULL,     -- CHEMBL1234567
    pref_name       VARCHAR,
    max_phase       FLOAT,
    molecule_type   VARCHAR,              -- Small molecule, Protein, etc.
    inchi           VARCHAR,
    inchikey        VARCHAR,
    canonical_smiles VARCHAR,
    standard_inchi  VARCHAR,
    aromatic_rings  INT,
    heavy_atoms     INT,
    hbd             INT,
    hba             INT,
    mw_freebase     FLOAT,
    alogp           FLOAT,
    psa             FLOAT,
    loaded_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'ChEMBL compound structures and drug-likeness properties';

-- Bioactivities
CREATE TABLE IF NOT EXISTS CHEMBL.ACTIVITIES (
    activity_id     NUMBER,
    assay_id        NUMBER,
    doc_id          NUMBER,
    record_id       NUMBER,
    molregno        NUMBER,
    chembl_id       VARCHAR,
    standard_type   VARCHAR,    -- IC50, Ki, Kd, EC50, etc.
    standard_value  FLOAT,
    standard_units  VARCHAR,    -- nM, uM, etc.
    standard_relation VARCHAR,
    activity_comment VARCHAR,
    pchembl_value   FLOAT,      -- -log10(standard_value in M)
    data_validity_comment VARCHAR
)
COMMENT = 'ChEMBL bioactivity measurements';

-- Targets
CREATE TABLE IF NOT EXISTS CHEMBL.TARGET_DICTIONARY (
    tid             NUMBER,
    chembl_id       VARCHAR NOT NULL,
    target_type     VARCHAR,
    pref_name       VARCHAR,
    tax_id          NUMBER,
    organism        VARCHAR,
    species_group_flag BOOLEAN
)
COMMENT = 'ChEMBL target definitions';

-- Assays
CREATE TABLE IF NOT EXISTS CHEMBL.ASSAYS (
    assay_id        NUMBER,
    chembl_id       VARCHAR,
    assay_type      VARCHAR,
    description     VARCHAR,
    assay_organism  VARCHAR,
    tid             NUMBER
)
COMMENT = 'ChEMBL assay definitions';

-- Load sequence (after staging ChEMBL TSV exports):
-- COPY INTO CHEMBL.MOLECULE_DICTIONARY FROM @CHEMBL.CHEMBL_STAGE/chembl_molecule_dictionary.tsv ...
-- COPY INTO CHEMBL.ACTIVITIES FROM @CHEMBL.CHEMBL_STAGE/chembl_activities.tsv ...
-- COPY INTO CHEMBL.TARGET_DICTIONARY FROM @CHEMBL.CHEMBL_STAGE/chembl_target_dictionary.tsv ...
-- COPY INTO CHEMBL.ASSAYS FROM @CHEMBL.CHEMBL_STAGE/chembl_assays.tsv ...

-- Refresh task (monthly)
CREATE OR REPLACE TASK CHEMBL.TASK_REFRESH_CHEMBL
  WAREHOUSE = WORKBENCH_ML
  SCHEDULE = 'USING CRON 0 3 1 * * UTC'
  COMMENT = 'Monthly ChEMBL refresh'
AS SELECT CURRENT_TIMESTAMP();  -- Placeholder: actual refresh logic TBD

-- Verification
SELECT 'MOLECULE_DICTIONARY' AS tbl, COUNT(*) AS row_count FROM CHEMBL.MOLECULE_DICTIONARY
UNION ALL SELECT 'ACTIVITIES', COUNT(*) FROM CHEMBL.ACTIVITIES
UNION ALL SELECT 'TARGET_DICTIONARY', COUNT(*) FROM CHEMBL.TARGET_DICTIONARY
UNION ALL SELECT 'ASSAYS', COUNT(*) FROM CHEMBL.ASSAYS;
