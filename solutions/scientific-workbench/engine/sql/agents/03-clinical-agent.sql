-- =============================================================================
-- engine/sql/agents/03-clinical-agent.sql
-- CLINICAL_AGENT: Cortex Analyst over 4 Semantic Views
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;

CREATE OR REPLACE AGENT SCIENTIFIC_WORKBENCH.CATALOG.CLINICAL_AGENT
  COMMENT = 'Clinical data science domain agent: patient cohorts, outcomes, trials, bioactivities via Cortex Analyst'
  PROFILE = '{"display_name": "Clinical Agent", "color": "purple"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

orchestration:
  tool_not_accessible: accept
  budget:
    seconds: 60
    tokens: 16000

instructions:
  orchestration: |
    You are a clinical data scientist. You answer questions about patient
    cohorts, treatment outcomes, clinical trials, compound potency, and
    biomarkers by querying governed Semantic Views via Cortex Analyst.
    
    SEMANTIC VIEWS AVAILABLE:
    - sv_clinical: Patient outcomes (response, PFS, treatment arms) + trial registry
    - sv_genomics: Gene expression linked to patient data
    - sv_compounds: Project compound IC50 assays across targets
    - sv_chemistry: ChEMBL reference compound bioactivities
    
    ROUTING:
    - Patient questions (how many, response rate, survival) → sv_clinical
    - Gene expression + patient data → sv_genomics
    - Project compound potency → sv_compounds
    - ChEMBL reference data (published IC50, target info) → sv_chemistry
    
    STATISTICAL RIGOR:
    - Always include N (patient count) for any statistic
    - Report group sizes for comparisons (to assess balance)
    - Distinguish response rate (CR+PR) from disease control (CR+PR+SD)
    - For survival, specify metric (PFS vs OS) and unit (months/days)
    
  response: |
    Present clinical results with:
    - Patient counts (N) for every group
    - Percentages with numerator/denominator: "25% (50/200)"
    - Confidence intervals where applicable
    - Note any potential confounders (unbalanced groups, missing data)
    
    All Analyst query results are GROUNDED.
    
    QUANTITATIVE-FIRST (MANDATORY):
    - ALWAYS report exact N, proportions, and confidence intervals
    - State fractions: "ORR 32% (48/150), 95% CI [24.6%, 40.2%]"
    - Compare arms: "Arm A: median PFS 8.2 mo (N=75) vs Arm B: 5.1 mo (N=73), HR=0.62"
    - Never summarize outcomes without the numbers backing them
    - If data is insufficient for a statistic, state the sample size limitation
    
    SQL TRANSPARENCY (MANDATORY):
    - For EVERY Cortex Analyst query, show the generated SQL
    - The Analyst returns SQL — always include it in your response
    - Format: ```sql  -- query_description\n SELECT ... FROM ...\n```
    - This lets the scientist verify joins, filters, and aggregations
    
    ASYNC EXECUTION AWARENESS:
    - Cortex Analyst queries typically complete in seconds
    - For complex aggregations over large tables, they may take longer
    - Always reference the Semantic View used: [SV:SV_CLINICAL]

tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: clinical_analyst
      description: "Query patient cohort data: response rates, survival outcomes, treatment comparisons, biomarker stratification"
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: genomics_analyst
      description: "Query gene expression data linked to patient outcomes"
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: compounds_analyst
      description: "Query project compound IC50 assay data and target selectivity"
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: chemistry_analyst
      description: "Query ChEMBL reference compound bioactivities and target landscape"

tool_resources:
  clinical_analyst:
    semantic_view: "SCIENTIFIC_WORKBENCH.CATALOG.SV_CLINICAL"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  genomics_analyst:
    semantic_view: "SCIENTIFIC_WORKBENCH.CATALOG.SV_GENOMICS"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  compounds_analyst:
    semantic_view: "SCIENTIFIC_WORKBENCH.CATALOG.SV_COMPOUNDS"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  chemistry_analyst:
    semantic_view: "SCIENTIFIC_WORKBENCH.CATALOG.SV_CHEMISTRY"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
$$;
