-- =============================================================================
-- data/semantic_views/sv_chemistry.sql
-- Semantic View for natural language querying over chemical data (ChEMBL)
-- =============================================================================

CREATE OR REPLACE SEMANTIC VIEW SCIENTIFIC_WORKBENCH.CATALOG.SV_CHEMISTRY
  TABLES (
    WORKBENCH_REFERENCE.CHEMBL.MOLECULE_DICTIONARY
      PRIMARY KEY (CHEMBL_ID)
      COMMENT = 'ChEMBL compound structures, drug-likeness, and development phase',
    WORKBENCH_REFERENCE.CHEMBL.ACTIVITIES
      PRIMARY KEY (ACTIVITY_ID)
      COMMENT = 'ChEMBL bioactivity measurements (IC50, Ki, Kd, EC50)',
    -- ACTIVITIES has no TID column, so activities cannot join targets
    -- directly. ChEMBL routes that join through ASSAYS
    -- (activities.assay_id -> assays.assay_id, assays.tid -> targets.tid),
    -- so ASSAYS is included here as the bridge table. Without it the view
    -- failed with: 000904 (42000) invalid identifier 'TID'.
    WORKBENCH_REFERENCE.CHEMBL.ASSAYS
      PRIMARY KEY (ASSAY_ID)
      COMMENT = 'ChEMBL assays — bridges bioactivities to their biological target',
    WORKBENCH_REFERENCE.CHEMBL.TARGET_DICTIONARY
      PRIMARY KEY (TID)
      COMMENT = 'ChEMBL biological targets — proteins, cell lines, organisms'
  )
  RELATIONSHIPS (
    ACTIVITY_COMPOUND AS ACTIVITIES(CHEMBL_ID) REFERENCES MOLECULE_DICTIONARY(CHEMBL_ID),
    ACTIVITY_ASSAY    AS ACTIVITIES(ASSAY_ID)  REFERENCES ASSAYS(ASSAY_ID),
    ASSAY_TARGET      AS ASSAYS(TID)           REFERENCES TARGET_DICTIONARY(TID)
  )
  DIMENSIONS (
    MOLECULE_DICTIONARY.COMPOUND_ID     AS CHEMBL_ID
      COMMENT = 'ChEMBL compound identifier',
    MOLECULE_DICTIONARY.COMPOUND_NAME     AS PREF_NAME
      COMMENT = 'Preferred compound or drug name',
    MOLECULE_DICTIONARY.MOLECULE_TYPE AS MOLECULE_TYPE
      COMMENT = 'Molecule class'
      SAMPLE_VALUES ('Small molecule', 'Protein', 'Antibody', 'Enzyme') IS_ENUM,
    MOLECULE_DICTIONARY.INCHIKEY      AS INCHIKEY
      COMMENT = 'Standard InChIKey for unambiguous chemical identity',
    MOLECULE_DICTIONARY.SMILES AS CANONICAL_SMILES
      COMMENT = 'Canonical SMILES molecular structure',
    MOLECULE_DICTIONARY.MAX_PHASE     AS MAX_PHASE
      COMMENT = 'Maximum clinical development phase (4 = approved)'
      SAMPLE_VALUES ('0', '1', '2', '3', '4') IS_ENUM,
    TARGET_DICTIONARY.TARGET_NAME       AS PREF_NAME
      COMMENT = 'Target protein or complex name',
    TARGET_DICTIONARY.TARGET_ORGANISM        AS ORGANISM
      COMMENT = 'Target organism' SAMPLE_VALUES ('Homo sapiens', 'Mus musculus') IS_ENUM,
    ACTIVITIES.ACTIVITY_TYPE          AS STANDARD_TYPE
      COMMENT = 'Bioactivity measurement type'
      SAMPLE_VALUES ('IC50', 'Ki', 'Kd', 'EC50', 'GI50', 'Potency') IS_ENUM,
    ACTIVITIES.ACTIVITY_UNITS         AS STANDARD_UNITS
      COMMENT = 'Measurement units'
      SAMPLE_VALUES ('nM', 'uM', 'mM') IS_ENUM,
    ACTIVITIES.ACTIVITY_RELATION      AS STANDARD_RELATION
      SAMPLE_VALUES ('=', '<', '>', '<=', '>=') IS_ENUM
  )
  METRICS (
    MOLECULE_DICTIONARY.COMPOUND_COUNT AS COUNT(DISTINCT CHEMBL_ID)
      COMMENT = 'Number of distinct compounds',
    ACTIVITIES.AVG_PCHEMBL      AS AVG(PCHEMBL_VALUE)
      COMMENT = 'Average pChEMBL potency (higher = more potent; IC50 1nM = pChEMBL 9)',
    ACTIVITIES.MAX_PCHEMBL      AS MAX(PCHEMBL_VALUE)
      COMMENT = 'Most potent pChEMBL value for a compound-target pair',
    ACTIVITIES.AVG_IC50_NM      AS AVG(STANDARD_VALUE)
      COMMENT = 'Average activity value in stated units',
    MOLECULE_DICTIONARY.AVG_MW  AS AVG(MW_FREEBASE)
      COMMENT = 'Average molecular weight (Da)',
    MOLECULE_DICTIONARY.AVG_LOGP AS AVG(ALOGP)
      COMMENT = 'Average calculated LogP'
  )
  COMMENT = 'Chemistry semantic layer — ChEMBL compound bioactivities, drug-likeness, and target interactions'
  AI_SQL_GENERATION 'Use AVG_PCHEMBL or MAX_PCHEMBL for potency comparisons (higher = more potent). Join ACTIVITIES to MOLECULE_DICTIONARY on CHEMBL_ID, and reach TARGET_DICTIONARY via ASSAYS (activities.assay_id = assays.assay_id, assays.tid = target_dictionary.tid). Filter STANDARD_TYPE = IC50 for most potency analyses. 1 nM IC50 equals pChEMBL 9.'
  AI_VERIFIED_QUERIES (
    POTENT_COMPOUNDS AS (
      QUESTION 'What are the most potent compounds against human targets by IC50?'
      VERIFIED_AT 1724803200 VERIFIED_BY '(STEWARD = deven.atnoor)'
      SQL 'SELECT m.pref_name AS compound, t.pref_name AS target, MAX(a.pchembl_value) AS best_pchembl
           FROM WORKBENCH_REFERENCE.CHEMBL.MOLECULE_DICTIONARY m
           JOIN WORKBENCH_REFERENCE.CHEMBL.ACTIVITIES a ON m.chembl_id = a.chembl_id
           JOIN WORKBENCH_REFERENCE.CHEMBL.ASSAYS s ON a.assay_id = s.assay_id
           JOIN WORKBENCH_REFERENCE.CHEMBL.TARGET_DICTIONARY t ON s.tid = t.tid
           WHERE a.standard_type = ''IC50'' AND a.pchembl_value IS NOT NULL
             AND t.organism = ''Homo sapiens''
           GROUP BY 1, 2
           ORDER BY best_pchembl DESC
           LIMIT 20'
    )
  );
