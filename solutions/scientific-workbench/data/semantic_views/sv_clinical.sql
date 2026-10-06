-- =============================================================================
-- data/semantic_views/sv_clinical.sql
-- Semantic View for natural language querying over clinical data
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW SCIENTIFIC_WORKBENCH.CATALOG.SV_CLINICAL
  TABLES (
    WORKBENCH_PROJECTS.DEMO_NSCLC.PATIENTS
      PRIMARY KEY (PATIENT_ID)
      COMMENT = 'NSCLC patient cohort with clinical, molecular, and outcome data',
    WORKBENCH_REFERENCE.CLINICAL.STUDIES
      PRIMARY KEY (NCT_ID)
      COMMENT = 'ClinicalTrials.gov study registry',
    WORKBENCH_REFERENCE.CLINICAL.INTERVENTIONS
      PRIMARY KEY (NCT_ID)
      COMMENT = 'Trial interventions (drugs, biologics, procedures)'
  )
  RELATIONSHIPS (
    TRIAL_INTERVENTION AS INTERVENTIONS(NCT_ID) REFERENCES STUDIES(NCT_ID)
  )
  DIMENSIONS (
    PATIENTS.PATIENT_ID            AS PATIENT_ID
      COMMENT = 'Patient identifier',
    PATIENTS.TREATMENT_ARM         AS TREATMENT_ARM
      COMMENT = 'Treatment arm' SAMPLE_VALUES ('Sotorasib', 'Chemo', 'Combo', 'Control') IS_ENUM,
    PATIENTS.RESPONSE_GROUP        AS RESPONSE_GROUP
      COMMENT = 'Best RECIST response' SAMPLE_VALUES ('CR', 'PR', 'SD', 'PD') IS_ENUM,
    PATIENTS.KRAS_MUTATION         AS KRAS_MUTATION
      COMMENT = 'KRAS mutation' SAMPLE_VALUES ('G12C', 'G12D', 'G12V', 'WT') IS_ENUM,
    PATIENTS.SEX                   AS SEX
      COMMENT = 'Patient sex' SAMPLE_VALUES ('M', 'F') IS_ENUM,
    PATIENTS.SMOKING_STATUS        AS SMOKING_STATUS
      COMMENT = 'Smoking history' SAMPLE_VALUES ('Never', 'Former', 'Current') IS_ENUM,
    PATIENTS.PRIOR_LINES           AS PRIOR_LINES
      COMMENT = 'Number of prior treatment lines',
    STUDIES.TRIAL_ID                 AS NCT_ID
      COMMENT = 'ClinicalTrials.gov identifier (NCT number)',
    STUDIES.TRIAL_NAME            AS BRIEF_TITLE
      COMMENT = 'Short trial title',
    STUDIES.TRIAL_STATUS         AS OVERALL_STATUS
      COMMENT = 'Current trial status'
      SAMPLE_VALUES ('Recruiting', 'Completed', 'Active, not recruiting', 'Withdrawn') IS_ENUM,
    STUDIES.TRIAL_PHASE                  AS PHASE
      COMMENT = 'Clinical trial phase'
      SAMPLE_VALUES ('Phase 1', 'Phase 2', 'Phase 3', 'Phase 1/2', 'Phase 2/3', 'N/A') IS_ENUM,
    STUDIES.TRIAL_SPONSOR                AS SPONSOR
      COMMENT = 'Primary sponsor organization',
    INTERVENTIONS.DRUG_NAME AS INTERVENTION_NAME
      COMMENT = 'Drug or intervention name',
    INTERVENTIONS.INTERVENTION_TYPE AS INTERVENTION_TYPE
      COMMENT = 'Intervention category'
      SAMPLE_VALUES ('Drug', 'Biological', 'Device', 'Procedure', 'Other') IS_ENUM
  )
  METRICS (
    PATIENTS.PATIENT_COUNT          AS COUNT(DISTINCT PATIENT_ID)
      COMMENT = 'Number of patients',
    PATIENTS.RESPONSE_RATE          AS
      COUNT_IF(RESPONSE_GROUP IN ('CR', 'PR')) * 100.0 / NULLIF(COUNT(PATIENT_ID), 0)
      COMMENT = 'Objective response rate (%)',
    PATIENTS.MEDIAN_PFS_MONTHS      AS MEDIAN(PFS_MONTHS)
      COMMENT = 'Median progression-free survival (months)',
    PATIENTS.AVG_AGE                AS AVG(AGE)
      COMMENT = 'Mean patient age',
    STUDIES.TRIAL_COUNT             AS COUNT(DISTINCT NCT_ID)
      COMMENT = 'Number of clinical trials'
  )
  COMMENT = 'Clinical semantic layer — patient cohort outcomes and clinical trial landscape'
  AI_SQL_GENERATION 'For response analysis, group by RESPONSE_GROUP and filter responders with RESPONSE_GROUP IN (''CR'',''PR''). Use MEDIAN(PFS_MONTHS) for survival comparisons. For trial analysis, group by PHASE or STATUS. Patients and trial data are not joined — query them separately.'
  AI_VERIFIED_QUERIES (
    RESPONSE_DISTRIBUTION AS (
      QUESTION 'How many patients responded to treatment?'
      VERIFIED_AT 1724803200 VERIFIED_BY '(STEWARD = deven.atnoor)'
      SQL 'SELECT response_group, COUNT(patient_id) AS patient_count,
                  ROUND(COUNT(patient_id) * 100.0 / SUM(COUNT(patient_id)) OVER(), 1) AS pct
           FROM WORKBENCH_PROJECTS.DEMO_NSCLC.PATIENTS
           GROUP BY response_group
           ORDER BY patient_count DESC'
    ),
    PHASE3_TRIALS AS (
      QUESTION 'How many Phase 3 trials are currently recruiting?'
      VERIFIED_AT 1724803200 VERIFIED_BY '(STEWARD = deven.atnoor)'
      SQL 'SELECT COUNT(DISTINCT nct_id) AS trial_count
           FROM WORKBENCH_REFERENCE.CLINICAL.STUDIES
           WHERE phase ILIKE ''%phase 3%''
             AND overall_status ILIKE ''%recruiting%'''
    )
  );
