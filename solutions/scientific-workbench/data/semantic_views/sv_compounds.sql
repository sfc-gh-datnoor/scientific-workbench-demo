-- =============================================================================
-- data/semantic_views/sv_compounds.sql
-- Semantic View over synthetic compound + assay project data
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW SCIENTIFIC_WORKBENCH.CATALOG.SV_COMPOUNDS
  TABLES (
    WORKBENCH_PROJECTS.DEMO_COMPOUNDS.COMPOUNDS
      PRIMARY KEY (COMPOUND_ID)
      COMMENT = '1000 synthetic drug candidates across 4 projects',
    WORKBENCH_PROJECTS.DEMO_COMPOUNDS.ASSAYS
      PRIMARY KEY (ASSAY_ID)
      COMMENT = '5000 IC50 bioactivity measurements'
  )
  RELATIONSHIPS (
    ASSAY_COMPOUND AS ASSAYS(COMPOUND_ID) REFERENCES COMPOUNDS(COMPOUND_ID)
  )
  DIMENSIONS (
    COMPOUNDS.COMPOUND_ID AS COMPOUND_ID COMMENT = 'Compound identifier',
    COMPOUNDS.PROJECT     AS PROJECT COMMENT = 'Drug project'
      SAMPLE_VALUES ('KRAS_P1', 'JAK2_P2', 'EGFR_P3', 'CDK_P4') IS_ENUM,
    COMPOUNDS.SERIES      AS SERIES COMMENT = 'Chemical series within project',
    COMPOUNDS.SMILES      AS SMILES COMMENT = 'SMILES molecular structure',
    COMPOUNDS.INCHIKEY    AS INCHIKEY COMMENT = 'Standard InChIKey',
    ASSAYS.TARGET         AS TARGET COMMENT = 'Protein target'
      SAMPLE_VALUES ('KRAS_G12C', 'JAK2', 'EGFR', 'ALK', 'MET', 'BRAF_V600E', 'CDK4_6', 'BTK', 'PI3K_alpha') IS_ENUM,
    ASSAYS.ASSAY_TYPE     AS ASSAY_TYPE COMMENT = 'Measurement type'
      SAMPLE_VALUES ('IC50') IS_ENUM
  )
  METRICS (
    COMPOUNDS.COMPOUND_COUNT AS COUNT(DISTINCT COMPOUND_ID) COMMENT = 'Number of compounds',
    COMPOUNDS.AVG_MW         AS AVG(MW)   COMMENT = 'Average molecular weight (Da)',
    COMPOUNDS.AVG_LOGP       AS AVG(LOGP) COMMENT = 'Average lipophilicity (LogP)',
    ASSAYS.AVG_IC50          AS AVG(VALUE_NM) COMMENT = 'Average IC50 (nM) — lower is more potent',
    ASSAYS.MIN_IC50          AS MIN(VALUE_NM) COMMENT = 'Best IC50 (nM)',
    ASSAYS.ASSAY_COUNT       AS COUNT(DISTINCT ASSAY_ID) COMMENT = 'Total assay measurements'
  )
  COMMENT = 'Compound project semantic layer — drug candidates with IC50 assay results'
  AI_SQL_GENERATION 'Use MIN(VALUE_NM) for best potency. Group by TARGET for selectivity profiles. Join ASSAYS to COMPOUNDS on COMPOUND_ID. Lower IC50 = more potent. Convert nM to pIC50 with -LOG10(VALUE_NM * 1e-9).'
  AI_VERIFIED_QUERIES (
    MOST_POTENT_BY_TARGET AS (
      QUESTION 'What are the most potent compounds for each target?'
      VERIFIED_AT 1724803200 VERIFIED_BY '(STEWARD = deven.atnoor)'
      SQL 'SELECT a.target, c.compound_id, c.project, MIN(a.value_nm) AS best_ic50_nm
           FROM WORKBENCH_PROJECTS.DEMO_COMPOUNDS.COMPOUNDS c
           JOIN WORKBENCH_PROJECTS.DEMO_COMPOUNDS.ASSAYS a ON c.compound_id = a.compound_id
           GROUP BY 1, 2, 3
           QUALIFY ROW_NUMBER() OVER (PARTITION BY a.target ORDER BY MIN(a.value_nm)) <= 3
           ORDER BY a.target, best_ic50_nm'
    )
  );
