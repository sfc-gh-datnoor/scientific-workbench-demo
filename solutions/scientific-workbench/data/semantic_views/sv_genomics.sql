-- =============================================================================
-- data/semantic_views/sv_genomics.sql
-- Semantic View for natural language querying over genomics + patient data
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW SCIENTIFIC_WORKBENCH.CATALOG.SV_GENOMICS
  TABLES (
    WORKBENCH_PROJECTS.DEMO_NSCLC.GENE_EXPRESSION
      PRIMARY KEY (PATIENT_ID, GENE_SYMBOL)
      COMMENT = 'Patient gene expression matrix (log2 normalized)',
    WORKBENCH_PROJECTS.DEMO_NSCLC.PATIENTS
      PRIMARY KEY (PATIENT_ID)
      COMMENT = 'NSCLC patient cohort with clinical and molecular annotations',
    WORKBENCH_REFERENCE.GENOMICS.HGNC_GENES
      PRIMARY KEY (APPROVED_SYMBOL)
      COMMENT = 'HGNC approved gene nomenclature'
  )
  RELATIONSHIPS (
    EXPRESSION_PATIENT AS GENE_EXPRESSION(PATIENT_ID) REFERENCES PATIENTS(PATIENT_ID),
    EXPRESSION_GENE    AS GENE_EXPRESSION(GENE_SYMBOL) REFERENCES HGNC_GENES(APPROVED_SYMBOL)
  )
  DIMENSIONS (
    GENE_EXPRESSION.GENE_SYMBOL    AS GENE_SYMBOL
      COMMENT = 'HGNC approved gene symbol (e.g. KRAS, TP53, EGFR)',
    HGNC_GENES.GENE_NAME       AS APPROVED_NAME
      COMMENT = 'Full gene name',
    HGNC_GENES.LOCUS_TYPE          AS LOCUS_TYPE
      COMMENT = 'Gene biotype'
      SAMPLE_VALUES ('protein-coding gene', 'RNA, non-coding', 'pseudogene') IS_ENUM,
    HGNC_GENES.CHROMOSOME          AS CHROMOSOME
      COMMENT = 'Chromosome location',
    PATIENTS.PATIENT_ID            AS PATIENT_ID
      COMMENT = 'Patient identifier',
    PATIENTS.KRAS_MUTATION         AS KRAS_MUTATION
      COMMENT = 'KRAS mutation type'
      SAMPLE_VALUES ('G12C', 'G12D', 'G12V', 'G13D', 'WT') IS_ENUM,
    PATIENTS.RESPONSE_GROUP        AS RESPONSE_GROUP
      COMMENT = 'Best treatment response'
      SAMPLE_VALUES ('CR', 'PR', 'SD', 'PD') IS_ENUM,
    PATIENTS.TREATMENT_ARM         AS TREATMENT_ARM
      COMMENT = 'Treatment arm'
      SAMPLE_VALUES ('Sotorasib', 'Chemo', 'Combo', 'Control') IS_ENUM,
    PATIENTS.SEX                   AS SEX
      COMMENT = 'Patient sex' SAMPLE_VALUES ('M', 'F') IS_ENUM,
    PATIENTS.SMOKING_STATUS        AS SMOKING_STATUS
      COMMENT = 'Smoking history'
      SAMPLE_VALUES ('Never', 'Former', 'Current') IS_ENUM
  )
  METRICS (
    GENE_EXPRESSION.AVG_EXPRESSION  AS AVG(EXPRESSION_VALUE)
      COMMENT = 'Average gene expression value (log2 normalized)',
    GENE_EXPRESSION.MAX_EXPRESSION  AS MAX(EXPRESSION_VALUE)
      COMMENT = 'Maximum expression value across samples',
    PATIENTS.PATIENT_COUNT          AS COUNT(DISTINCT PATIENT_ID)
      COMMENT = 'Number of patients',
    PATIENTS.MEDIAN_PFS             AS MEDIAN(PFS_MONTHS)
      COMMENT = 'Median progression-free survival in months',
    PATIENTS.AVG_AGE                AS AVG(AGE)
      COMMENT = 'Average patient age',
    PATIENTS.RESPONSE_RATE          AS
      COUNT_IF(RESPONSE_GROUP IN ('CR', 'PR')) * 100.0 / NULLIF(COUNT(PATIENT_ID), 0)
      COMMENT = 'Objective response rate (%)'
  )
  COMMENT = 'Genomics semantic layer — gene expression joined with patient clinical data'
  AI_SQL_GENERATION 'Join GENE_EXPRESSION to PATIENTS on PATIENT_ID for patient-level expression queries. Use RESPONSE_GROUP IN (''CR'',''PR'') for responders. Use AVG_EXPRESSION to compare expression levels across groups. Use PATIENT_COUNT and RESPONSE_RATE for cohort summaries.'
  AI_VERIFIED_QUERIES (
    KRAS_G12C_PATIENTS AS (
      QUESTION 'How many patients have KRAS G12C mutations?'
      VERIFIED_AT 1724803200 VERIFIED_BY '(STEWARD = deven.atnoor)'
      SQL 'SELECT COUNT(*) AS kras_g12c_patients
           FROM WORKBENCH_PROJECTS.DEMO_NSCLC.PATIENTS
           WHERE kras_mutation = ''G12C'''
    ),
    PFS_BY_RESPONSE AS (
      QUESTION 'What is the median progression-free survival by response group?'
      VERIFIED_AT 1724803200 VERIFIED_BY '(STEWARD = deven.atnoor)'
      SQL 'SELECT response_group, COUNT(*) AS n_patients, MEDIAN(pfs_months) AS median_pfs_months
           FROM WORKBENCH_PROJECTS.DEMO_NSCLC.PATIENTS
           GROUP BY response_group
           ORDER BY median_pfs_months DESC'
    )
  );
