-- =============================================================================
-- data/synthetic/load_synthetic_data.sql
-- Self-contained synthetic data generator — pure SQL, no CSV/PUT/COPY needed
-- Run AFTER: setup/01-databases-and-schemas.sql (creates WORKBENCH_PROJECTS DB)
-- =============================================================================
-- Generates 6 demo datasets using Snowflake GENERATOR() + random functions:
--   1. PATIENTS           200 NSCLC patients with KRAS mutations + outcomes
--   2. GENE_EXPRESSION    100K measurements (500 genes x 200 patients)
--   3. COMPOUNDS          1000 drug candidates with properties
--   4. ASSAYS             5000 IC50 measurements across 9 targets
--   5. TRIALS             200 KRAS/NSCLC-focused clinical trials
--   6. PROTEINS           15 druggable oncology targets with sequences
--
-- All data is generated in-database using UNIFORM(), NORMAL(), RANDOM().
-- No external files, stages, or PUT commands required.
-- Idempotent: uses CREATE OR REPLACE for all tables.
-- =============================================================================

USE DATABASE WORKBENCH_PROJECTS;
USE WAREHOUSE WORKBENCH_S;

-- =============================================================================
-- 1. NSCLC PATIENT COHORT (200 patients)
-- Persona #1 Computational Biologist, #3 Clinical Data Scientist
-- =============================================================================
USE SCHEMA DEMO_NSCLC;

CREATE OR REPLACE TABLE DEMO_NSCLC.PATIENTS (
    patient_id      VARCHAR NOT NULL PRIMARY KEY,
    age             INT,
    sex             VARCHAR,
    smoking_status  VARCHAR,
    stage           VARCHAR,
    kras_mutation   VARCHAR,
    stk11_status    VARCHAR,
    pd_l1_tps       INT,
    treatment_arm   VARCHAR,
    response_group  VARCHAR,
    pfs_months      FLOAT,
    pfs_event       INT,
    prior_lines     INT
) COMMENT = 'Synthetic NSCLC patient cohort: 200 patients with KRAS mutations and treatment outcomes';

INSERT INTO DEMO_NSCLC.PATIENTS
WITH raw_patients AS (
    SELECT
        'PT-' || LPAD(ROW_NUMBER() OVER (ORDER BY 1), 4, '0')         AS patient_id,
        UNIFORM(45, 82, RANDOM())                                      AS age,
        CASE WHEN UNIFORM(0, 1, RANDOM()) = 0 THEN 'M' ELSE 'F' END   AS sex,
        CASE
            WHEN UNIFORM(1, 100, RANDOM()) <= 25 THEN 'Never'
            WHEN UNIFORM(1, 100, RANDOM()) <= 70 THEN 'Former'
            ELSE 'Current'
        END                                                            AS smoking_status,
        CASE WHEN UNIFORM(0, 1, RANDOM()) = 0 THEN 'IIIB' ELSE 'IV' END AS stage,
        CASE
            WHEN UNIFORM(1, 100, RANDOM()) <= 35 THEN 'G12C'
            WHEN UNIFORM(1, 100, RANDOM()) <= 55 THEN 'G12D'
            WHEN UNIFORM(1, 100, RANDOM()) <= 80 THEN 'G12V'
            WHEN UNIFORM(1, 100, RANDOM()) <= 90 THEN 'G13D'
            ELSE 'WT'
        END                                                            AS kras_mutation,
        CASE WHEN UNIFORM(0, 1, RANDOM()) = 0 THEN 'Mutant' ELSE 'WT' END AS stk11_status,
        UNIFORM(0, 100, RANDOM())                                      AS pd_l1_tps,
        CASE UNIFORM(0, 3, RANDOM())
            WHEN 0 THEN 'Sotorasib'
            WHEN 1 THEN 'Chemo'
            WHEN 2 THEN 'Combo'
            ELSE 'Control'
        END                                                            AS treatment_arm,
        UNIFORM(1, 100, RANDOM())                                      AS _response_roll,
        UNIFORM(0, 2, RANDOM())                                        AS prior_lines
    FROM TABLE(GENERATOR(ROWCOUNT => 200))
),
with_response AS (
    SELECT *,
        CASE
            -- KRAS G12C + Sotorasib: better response
            WHEN kras_mutation = 'G12C' AND treatment_arm = 'Sotorasib' THEN
                CASE WHEN _response_roll <= 15 THEN 'CR'
                     WHEN _response_roll <= 45 THEN 'PR'
                     WHEN _response_roll <= 75 THEN 'SD'
                     ELSE 'PD' END
            -- Combo: moderate response
            WHEN treatment_arm = 'Combo' THEN
                CASE WHEN _response_roll <= 10 THEN 'CR'
                     WHEN _response_roll <= 35 THEN 'PR'
                     WHEN _response_roll <= 70 THEN 'SD'
                     ELSE 'PD' END
            -- Other: poor response
            ELSE
                CASE WHEN _response_roll <= 5  THEN 'CR'
                     WHEN _response_roll <= 20 THEN 'PR'
                     WHEN _response_roll <= 50 THEN 'SD'
                     ELSE 'PD' END
        END AS response_group
    FROM raw_patients
)
SELECT
    patient_id, age, sex, smoking_status, stage,
    kras_mutation, stk11_status, pd_l1_tps, treatment_arm,
    response_group,
    -- PFS correlated with response (months)
    GREATEST(0.5, ROUND(
        CASE response_group
            WHEN 'CR' THEN 18.0 + NORMAL(0, 5.4, RANDOM())
            WHEN 'PR' THEN 12.0 + NORMAL(0, 3.6, RANDOM())
            WHEN 'SD' THEN  7.0 + NORMAL(0, 2.1, RANDOM())
            ELSE            3.0 + NORMAL(0, 0.9, RANDOM())
        END, 1))                                                       AS pfs_months,
    -- Event: SD/PD always event=1; CR/PR 30% event
    CASE
        WHEN response_group IN ('SD', 'PD') THEN 1
        WHEN UNIFORM(1, 100, RANDOM()) <= 30 THEN 1
        ELSE 0
    END                                                                AS pfs_event,
    prior_lines
FROM with_response;

-- =============================================================================
-- 2. GENE EXPRESSION (500 genes x 200 patients = 100,000 rows)
-- =============================================================================

CREATE OR REPLACE TABLE DEMO_NSCLC.GENE_EXPRESSION (
    patient_id       VARCHAR NOT NULL,
    gene_symbol      VARCHAR NOT NULL,
    expression_value FLOAT,
    PRIMARY KEY (patient_id, gene_symbol)
) COMMENT = 'Synthetic gene expression: 500 genes x 200 patients (log2 normalized)';

INSERT INTO DEMO_NSCLC.GENE_EXPRESSION
WITH genes AS (
    -- 50 real oncology genes + 450 generic genes = 500 total
    SELECT column1 AS gene_symbol, ROW_NUMBER() OVER (ORDER BY column1) AS gene_idx
    FROM VALUES
        ('KRAS'),('TP53'),('EGFR'),('ALK'),('STK11'),('KEAP1'),('ROS1'),('MET'),('BRAF'),('ERBB2'),
        ('PIK3CA'),('NRAS'),('MAP2K1'),('CDKN2A'),('RB1'),('NF1'),('PTEN'),('AKT1'),('CTNNB1'),('SMAD4'),
        ('ARID1A'),('ATM'),('BRCA2'),('FGFR2'),('IDH1'),('JAK2'),('NOTCH1'),('PTPN11'),('RAF1'),('SHP2'),
        ('SOS1'),('MTOR'),('CDK4'),('CDK6'),('CCND1'),('MYC'),('BCL2'),('VEGFA'),('FLT3'),('KIT'),
        ('PDGFRA'),('RET'),('NTRK1'),('AXL'),('DDR2'),('FGFR1'),('FGFR3'),('ERBB3'),('ERBB4'),('TERT')
    UNION ALL
    SELECT 'GENE_' || LPAD(ROW_NUMBER() OVER (ORDER BY 1) + 49, 3, '0'), ROW_NUMBER() OVER (ORDER BY 1) + 50
    FROM TABLE(GENERATOR(ROWCOUNT => 450))
)
SELECT
    p.patient_id,
    g.gene_symbol,
    GREATEST(0, ROUND(
        -- Base expression ~ N(6, 2)
        6.0 + NORMAL(0, 2.0, RANDOM())
        -- Upregulate resistance genes in PD patients
        + CASE
            WHEN g.gene_symbol IN ('KRAS','EGFR','STK11','PTPN11')
                 AND p.response_group = 'PD'
            THEN NORMAL(1.5, 0.5, RANDOM())
            ELSE 0
          END
    , 3))                                                              AS expression_value
FROM DEMO_NSCLC.PATIENTS p
CROSS JOIN genes g;

-- =============================================================================
-- 3. COMPOUND LIBRARY (1000 compounds)
-- Persona #2 Medicinal Chemist, #8 AI Drug Discovery
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS WORKBENCH_PROJECTS.DEMO_COMPOUNDS;
USE SCHEMA DEMO_COMPOUNDS;

CREATE OR REPLACE TABLE DEMO_COMPOUNDS.COMPOUNDS (
    compound_id     VARCHAR NOT NULL PRIMARY KEY,
    smiles          VARCHAR,
    inchikey        VARCHAR,
    project         VARCHAR,
    series          VARCHAR,
    mw              FLOAT,
    logp            FLOAT,
    hbd             INT,
    hba             INT,
    tpsa            FLOAT,
    rotatable_bonds INT
) COMMENT = 'Synthetic compound library: 1000 drug candidates across 4 projects';

INSERT INTO DEMO_COMPOUNDS.COMPOUNDS
WITH scaffolds AS (
    SELECT column1 AS scaffold, ROW_NUMBER() OVER (ORDER BY 1) AS idx FROM VALUES
    ('c1ccc(NC(=O)c2ccc'),('c1ccncc1NC(=O)'),('CC(=O)Nc1ccc('),('O=C(Nc1ccccc1)'),
    ('c1ccc2c(c1)cc('),('CCOc1ccc(NC(=O)'),('Fc1ccc(NC(=O)c2'),('Clc1ccc(NC('),
    ('c1ccc(-c2nccn2)cc1'),('COc1ccc(CC(=O)Nc2')
),
projects AS (
    SELECT column1 AS project, ROW_NUMBER() OVER (ORDER BY 1) AS idx FROM VALUES
    ('KRAS_P1'),('JAK2_P2'),('EGFR_P3'),('CDK_P4')
),
caps AS (
    SELECT column1 AS cap, ROW_NUMBER() OVER (ORDER BY 1) AS idx FROM VALUES
    ('F'),('Cl'),('N'),('O'),('C')
),
base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY 1) AS rn,
        UNIFORM(1, 10, RANDOM()) AS scaffold_pick,
        UNIFORM(1, 4, RANDOM())  AS project_pick,
        UNIFORM(1, 5, RANDOM())  AS cap_pick,
        UNIFORM(1, 3, RANDOM())  AS paren_count,
        UNIFORM(1, 20, RANDOM()) AS series_num,
        NORMAL(420, 80, RANDOM()) AS mw_raw,
        NORMAL(3.0, 1.2, RANDOM()) AS logp_raw,
        UNIFORM(0, 4, RANDOM())  AS hbd,
        UNIFORM(1, 8, RANDOM())  AS hba,
        NORMAL(85, 30, RANDOM()) AS tpsa_raw,
        UNIFORM(2, 10, RANDOM()) AS rotatable_bonds
    FROM TABLE(GENERATOR(ROWCOUNT => 1000))
)
SELECT
    'CPD-' || LPAD(b.rn, 5, '0')                                     AS compound_id,
    s.scaffold || REPEAT(')', b.paren_count) || c.cap                  AS smiles,
    UPPER(SUBSTR(MD5('CPD-' || b.rn), 1, 27))                        AS inchikey,
    pr.project,
    'Series_' || b.series_num                                          AS series,
    ROUND(b.mw_raw, 1)                                                AS mw,
    ROUND(b.logp_raw, 2)                                              AS logp,
    b.hbd,
    b.hba,
    ROUND(b.tpsa_raw, 1)                                              AS tpsa,
    b.rotatable_bonds
FROM base b
  JOIN scaffolds s  ON s.idx = b.scaffold_pick
  JOIN projects pr  ON pr.idx = b.project_pick
  JOIN caps c       ON c.idx = b.cap_pick;

-- =============================================================================
-- 4. ASSAY RESULTS (5000 IC50 measurements)
-- =============================================================================

CREATE OR REPLACE TABLE DEMO_COMPOUNDS.ASSAYS (
    assay_id          VARCHAR NOT NULL PRIMARY KEY,
    compound_id       VARCHAR,
    target            VARCHAR,
    assay_type        VARCHAR,
    value_nm          FLOAT,
    selectivity_ratio FLOAT,
    experiment_date   DATE
) COMMENT = 'Synthetic IC50 assay results: 5000 measurements across 9 targets';

INSERT INTO DEMO_COMPOUNDS.ASSAYS
WITH targets AS (
    SELECT column1 AS target, ROW_NUMBER() OVER (ORDER BY 1) AS idx FROM VALUES
    ('KRAS_G12C'),('JAK2'),('EGFR'),('ALK'),('MET'),
    ('BRAF_V600E'),('CDK4_6'),('BTK'),('PI3K_alpha')
),
base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY 1) AS rn,
        UNIFORM(1, 1000, RANDOM())     AS cpd_pick,
        UNIFORM(1, 9, RANDOM())        AS target_pick,
        NORMAL(2, 1.5, RANDOM())       AS ic50_log,
        UNIFORM(0, 1, RANDOM())        AS has_selectivity,
        NORMAL(10, 5, RANDOM())        AS selectivity_raw,
        UNIFORM(0, 500, RANDOM())      AS day_offset
    FROM TABLE(GENERATOR(ROWCOUNT => 5000))
)
SELECT
    'ASY-' || LPAD(b.rn, 6, '0')                                     AS assay_id,
    'CPD-' || LPAD(b.cpd_pick, 5, '0')                               AS compound_id,
    t.target,
    'IC50'                                                             AS assay_type,
    ROUND(POW(10, b.ic50_log), 1)                                    AS value_nm,
    CASE WHEN b.has_selectivity = 1
         THEN ROUND(b.selectivity_raw, 1)
         ELSE NULL
    END                                                                AS selectivity_ratio,
    DATEADD('day', b.day_offset, '2025-01-01'::DATE)                 AS experiment_date
FROM base b
  JOIN targets t ON t.idx = b.target_pick;

-- =============================================================================
-- 5. CLINICAL TRIALS (200 trials)
-- Persona #3 Clinical Data Scientist
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS WORKBENCH_PROJECTS.DEMO_CLINICAL;
USE SCHEMA DEMO_CLINICAL;

CREATE OR REPLACE TABLE DEMO_CLINICAL.TRIALS (
    nct_id          VARCHAR NOT NULL PRIMARY KEY,
    brief_title     VARCHAR,
    overall_status  VARCHAR,
    phase           VARCHAR,
    start_date      DATE,
    sponsor         VARCHAR,
    condition       VARCHAR,
    intervention    VARCHAR,
    enrollment      INT
) COMMENT = 'Synthetic clinical trials: 200 KRAS/NSCLC-focused studies';

INSERT INTO DEMO_CLINICAL.TRIALS
WITH sponsors AS (
    SELECT column1 AS sponsor, ROW_NUMBER() OVER (ORDER BY 1) AS idx FROM VALUES
    ('Amgen'),('Mirati'),('Revolution Medicines'),('Sanofi'),('AstraZeneca'),
    ('Roche'),('Merck'),('Pfizer'),('Bristol-Myers Squibb'),('Eli Lilly')
),
conditions AS (
    SELECT column1 AS cond, ROW_NUMBER() OVER (ORDER BY 1) AS idx FROM VALUES
    ('Non-Small Cell Lung Cancer'),('Colorectal Cancer'),('Pancreatic Cancer'),
    ('Solid Tumors'),('KRAS G12C Mutant'),('Advanced NSCLC')
),
drugs AS (
    SELECT column1 AS drug, ROW_NUMBER() OVER (ORDER BY 1) AS idx FROM VALUES
    ('Sotorasib'),('Adagrasib'),('Divarasib'),('JDQ443'),('GDC-6036'),
    ('RMC-6236'),('Pembrolizumab'),('Docetaxel'),('Carboplatin'),('SHP2i')
),
phases AS (
    SELECT column1 AS phase, ROW_NUMBER() OVER (ORDER BY 1) AS idx FROM VALUES
    ('Phase 1'),('Phase 1/2'),('Phase 2'),('Phase 2/3'),('Phase 3')
),
statuses AS (
    SELECT column1 AS status, ROW_NUMBER() OVER (ORDER BY 1) AS idx FROM VALUES
    ('Recruiting'),('Active, not recruiting'),('Completed'),('Terminated')
),
base AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY 1)  AS rn,
        UNIFORM(1, 10, RANDOM())        AS sponsor_pick,
        UNIFORM(1, 6, RANDOM())         AS cond_pick,
        UNIFORM(1, 10, RANDOM())        AS drug_pick,
        UNIFORM(1, 5, RANDOM())         AS phase_pick,
        UNIFORM(1, 4, RANDOM())         AS status_pick,
        UNIFORM(0, 1800, RANDOM())      AS day_offset,
        UNIFORM(1, 3, RANDOM())         AS phase_num,
        UNIFORM(20, 500, RANDOM())      AS enrollment
    FROM TABLE(GENERATOR(ROWCOUNT => 200))
)
SELECT
    'NCT' || (10000000 + UNIFORM(0, 89999999, RANDOM()))::VARCHAR     AS nct_id,
    d.drug || ' in ' || c.cond || ': Phase ' || b.phase_num || ' Study' AS brief_title,
    st.status                                                          AS overall_status,
    ph.phase,
    DATEADD('day', b.day_offset, '2020-01-01'::DATE)                  AS start_date,
    sp.sponsor,
    c.cond                                                             AS condition,
    d.drug                                                             AS intervention,
    b.enrollment
FROM base b
  JOIN sponsors sp   ON sp.idx = b.sponsor_pick
  JOIN conditions c  ON c.idx  = b.cond_pick
  JOIN drugs d       ON d.idx  = b.drug_pick
  JOIN phases ph     ON ph.idx = b.phase_pick
  JOIN statuses st   ON st.idx = b.status_pick;

-- =============================================================================
-- 6. PROTEIN TARGETS (15 targets with sequences)
-- Persona #4 Structural Biologist
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS WORKBENCH_PROJECTS.DEMO_STRUCTURAL;
USE SCHEMA DEMO_STRUCTURAL;

CREATE OR REPLACE TABLE DEMO_STRUCTURAL.PROTEINS (
    gene_symbol       VARCHAR NOT NULL,
    protein_name      VARCHAR,
    uniprot_id        VARCHAR,
    sequence          VARCHAR,
    length            INT,
    pdb_ids           VARCHAR,
    organism          VARCHAR,
    druggability_score FLOAT
) COMMENT = 'Synthetic protein targets: 15 druggable cancer targets with sequences';

-- Real gene names, real protein names, real UniProt IDs, real PDB IDs.
-- Sequences are truncated/synthetic (random AA) for demo purposes.
INSERT INTO DEMO_STRUCTURAL.PROTEINS VALUES
('KRAS',   'GTPase KRas',                                 'P01116', 'MTEYKLVVVGAVGVGKSALTIQLIQNHFVDEYDPTIEDSY', 189,  '6OIM', 'Homo sapiens', 0.82),
('EGFR',   'Epidermal growth factor receptor',            'P00533', 'MRPSGTAGAALLALLAALCPASRALEEKKVCQGTSNKLTQL', 1210, '5UO9', 'Homo sapiens', 0.91),
('ALK',    'ALK tyrosine kinase receptor',                'Q9UM73', 'MAWDMKNIIFFAICLSTVLGAHSRNAAQVSGGPLCLQEVAR', 1620, '3GFT', 'Homo sapiens', 0.78),
('BRAF',   'Serine/threonine-protein kinase B-Raf',       'P15056', 'MAALSGGGGGGAEPGQALFNGDMEPEAGAGAGAAASSAADP', 766,  '6VJJ', 'Homo sapiens', 0.88),
('JAK2',   'Tyrosine-protein kinase JAK2',                'O60674', 'MGMACLTMTEMEGTSTSSIYQNGDISGNANSMKQIDPVLQV', 1132, '7RPZ', 'Homo sapiens', 0.85),
('MET',    'Hepatocyte growth factor receptor',           'P08581', 'MKAPAVLAPGILVLLFTLVQRSNGECKEALAKSEMNVNMKY', 1390, '3GFT', 'Homo sapiens', 0.79),
('PIK3CA', 'PI3-kinase p110-alpha catalytic subunit',     'P42336', 'MPPRPSSGELWGIHLMPPRILVECLLPNGMIVTLECLREAT', 1068, '6VJJ', 'Homo sapiens', 0.83),
('CDK4',   'Cyclin-dependent kinase 4',                   'P11802', 'MATSRYEPVAEIGVGAYGTVYKARDPHSGHFVALKSVRVPN', 303,  '5UO9', 'Homo sapiens', 0.76),
('CDK6',   'Cyclin-dependent kinase 6',                   'Q00534', 'MEKYDFEISPLPSGEHRVREFEVIGAVSLQERRREKYNGFQ', 326,  '5UO9', 'Homo sapiens', 0.74),
('BTK',    'Bruton tyrosine kinase',                      'Q06187', 'MAAVILESIFVSYFGSRRKNWVTQGFGNNLRGSGGSDIYEQ', 659,  '6OIM', 'Homo sapiens', 0.87),
('FGFR2',  'Fibroblast growth factor receptor 2',         'P21802', 'MVSWGRFICLVVVTMATLSLARPSFSLVEDTTLEPEEPPTKY', 821,  '7RPZ', 'Homo sapiens', 0.72),
('RET',    'Proto-oncogene tyrosine-protein kinase RET',  'P07949', 'MAATLLPVLLLFSALSADGARGLAVDRCERLGEELGCAQSP', 1114, '6VJJ', 'Homo sapiens', 0.80),
('SHP2',   'Tyrosine-protein phosphatase non-receptor 11','Q06124', 'MTSRRWFHPNITGVEAENLLLTRGVDGSFLARPSKSNPGQF', 593,  '6OIM', 'Homo sapiens', 0.84),
('SOS1',   'Son of sevenless homolog 1',                  'Q07889', 'MFSGSHRHPSFPEELDTSRIDHDFTPISTPEEPEGCRWGDPG', 1333, '7RPZ', 'Homo sapiens', 0.69),
('PTPN11', 'Tyrosine-protein phosphatase non-receptor 11','Q06124', 'MTSRRWFHPNITGVEAENLLLTRGVDGSFLARPSKSNPGQF', 593,  '3GFT', 'Homo sapiens', 0.84);

-- =============================================================================
-- REGISTER ALL DEMO DATASETS IN ASSET CATALOG
-- =============================================================================
USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;

INSERT INTO CATALOG.ASSETS (asset_id, asset_name, asset_type, description, domain, schema_name, owner)
SELECT * FROM VALUES
('DS-001', 'NSCLC Patient Cohort', 'dataset', '200 synthetic NSCLC patients with KRAS mutations, treatment arms, and survival outcomes', 'clinical,oncology', 'WORKBENCH_PROJECTS.DEMO_NSCLC', 'WORKBENCH_ADMIN'),
('DS-002', 'Gene Expression Matrix', 'dataset', '100K gene expression measurements (500 genes x 200 patients, log2 normalized)', 'genomics,transcriptomics', 'WORKBENCH_PROJECTS.DEMO_NSCLC', 'WORKBENCH_ADMIN'),
('DS-003', 'Compound Library', 'dataset', '1000 synthetic drug candidates across 4 projects with physicochemical properties', 'chemistry', 'WORKBENCH_PROJECTS.DEMO_COMPOUNDS', 'WORKBENCH_ADMIN'),
('DS-004', 'IC50 Assay Results', 'dataset', '5000 IC50 measurements across 9 oncology targets', 'chemistry,screening', 'WORKBENCH_PROJECTS.DEMO_COMPOUNDS', 'WORKBENCH_ADMIN'),
('DS-005', 'Clinical Trials', 'dataset', '200 KRAS/NSCLC-focused clinical trials with phases, sponsors, and interventions', 'clinical,trials', 'WORKBENCH_PROJECTS.DEMO_CLINICAL', 'WORKBENCH_ADMIN'),
('DS-006', 'Protein Targets', 'dataset', '15 druggable oncology targets with sequences, PDB IDs, and druggability scores', 'structural,protein', 'WORKBENCH_PROJECTS.DEMO_STRUCTURAL', 'WORKBENCH_ADMIN')
-- Snowflake has no ON CONFLICT clause (that is PostgreSQL). The previous
-- `ON CONFLICT DO NOTHING;` failed with:
--   001003 (42000): syntax error line 9 at position 0 unexpected 'ON'.
-- An anti-join on asset_id preserves the original intent, namely that
-- re-running this loader does not duplicate the catalog rows.
AS v(asset_id, asset_name, asset_type, description, domain, schema_name, owner)
WHERE v.asset_id NOT IN (SELECT asset_id FROM CATALOG.ASSETS);

-- =============================================================================
-- VERIFICATION
-- =============================================================================
SELECT 'PATIENTS' AS tbl, COUNT(*) AS row_count FROM WORKBENCH_PROJECTS.DEMO_NSCLC.PATIENTS
UNION ALL SELECT 'GENE_EXPRESSION', COUNT(*) FROM WORKBENCH_PROJECTS.DEMO_NSCLC.GENE_EXPRESSION
UNION ALL SELECT 'COMPOUNDS', COUNT(*) FROM WORKBENCH_PROJECTS.DEMO_COMPOUNDS.COMPOUNDS
UNION ALL SELECT 'ASSAYS', COUNT(*) FROM WORKBENCH_PROJECTS.DEMO_COMPOUNDS.ASSAYS
UNION ALL SELECT 'TRIALS', COUNT(*) FROM WORKBENCH_PROJECTS.DEMO_CLINICAL.TRIALS
UNION ALL SELECT 'PROTEINS', COUNT(*) FROM WORKBENCH_PROJECTS.DEMO_STRUCTURAL.PROTEINS;

-- =============================================================================
-- GRANTS
-- Without these the data loads but is unusable. The native analysis procedures
-- (RUN_DIFFERENTIAL_EXPRESSION, RUN_SURVIVAL_ANALYSIS) run EXECUTE AS OWNER,
-- so the owning role needs SELECT on these tables. Whichever role runs this
-- script owns the tables it creates, so if that is not SYSADMIN the procedures
-- fail with "Object ... does not exist or not authorized" even though the data
-- is present and queryable by the loader. Observed 2026-09-08 when the loader
-- was run as ACCOUNTADMIN: every genomics tool broke on a table that plainly
-- existed. WORKBENCH_SCIENTIST and WORKBENCH_VIEWER need read access for the
-- app and for interactive use.
-- =============================================================================
USE ROLE ACCOUNTADMIN;

GRANT USAGE ON DATABASE WORKBENCH_PROJECTS TO ROLE SYSADMIN;
GRANT USAGE ON ALL SCHEMAS IN DATABASE WORKBENCH_PROJECTS TO ROLE SYSADMIN;
GRANT SELECT ON ALL TABLES IN DATABASE WORKBENCH_PROJECTS TO ROLE SYSADMIN;
GRANT SELECT ON FUTURE TABLES IN DATABASE WORKBENCH_PROJECTS TO ROLE SYSADMIN;

GRANT USAGE ON DATABASE WORKBENCH_PROJECTS TO ROLE WORKBENCH_SCIENTIST;
GRANT USAGE ON ALL SCHEMAS IN DATABASE WORKBENCH_PROJECTS TO ROLE WORKBENCH_SCIENTIST;
GRANT SELECT ON ALL TABLES IN DATABASE WORKBENCH_PROJECTS TO ROLE WORKBENCH_SCIENTIST;
GRANT SELECT ON FUTURE TABLES IN DATABASE WORKBENCH_PROJECTS TO ROLE WORKBENCH_SCIENTIST;

GRANT USAGE ON DATABASE WORKBENCH_PROJECTS TO ROLE WORKBENCH_VIEWER;
GRANT USAGE ON ALL SCHEMAS IN DATABASE WORKBENCH_PROJECTS TO ROLE WORKBENCH_VIEWER;
GRANT SELECT ON ALL TABLES IN DATABASE WORKBENCH_PROJECTS TO ROLE WORKBENCH_VIEWER;
GRANT SELECT ON FUTURE TABLES IN DATABASE WORKBENCH_PROJECTS TO ROLE WORKBENCH_VIEWER;
