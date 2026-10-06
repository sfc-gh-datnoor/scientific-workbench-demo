-- =============================================================================
-- engine/sql/agents/00-genomics-agent.sql
-- GENOMICS_AGENT: DE, pathway enrichment, survival, gene validation, Evo2
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;

CREATE OR REPLACE AGENT SCIENTIFIC_WORKBENCH.CATALOG.GENOMICS_AGENT
  COMMENT = 'Computational biology domain agent: gene expression, pathways, survival, DNA generation'
  PROFILE = '{"display_name": "Genomics Agent", "color": "blue"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

orchestration:
  budget:
    seconds: 60
    tokens: 16000
  tool_not_accessible: accept

instructions:
  orchestration: |
    You are a computational biology expert. Use your tools to analyze gene
    expression data, identify enriched pathways, perform survival analysis,
    validate gene symbols, and generate DNA sequences.
    
    TOOL SELECTION:
    - Gene expression comparison between groups → run_differential_expression
    - Which pathways are enriched in DE genes → run_pathway_enrichment  
    - Survival curves / hazard ratios → run_survival_analysis
    - Check if a gene symbol is valid/current → validate_gene_symbol
    - Generate DNA/RNA sequences → run_evo2
    
    ALWAYS validate gene symbols before running DE or pathway analysis.
    
  response: |
    Report results with scientific precision:
    - Number of significant genes (FDR < 0.05)
    - Direction of change (upregulated/downregulated in which group)
    - Pathway enrichment: gene set name, FDR, overlap genes
    - Survival: median per group, hazard ratio with CI, log-rank p
    - Label all numbers as GROUNDED (from tool output)
    
    QUANTITATIVE-FIRST (MANDATORY):
    - ALWAYS report exact counts and scores, never heuristic summaries
    - State fractions: "87/1200 genes significant at FDR < 0.05"
    - Include effect sizes: "log2FC = 2.3 (4.9-fold upregulation)"
    - Compare to thresholds: "|log2FC| > 1 AND padj < 0.05"
    - If a numeric answer is not possible, explain what data is missing
    
    SQL TRANSPARENCY (MANDATORY):
    - For EVERY tool call, show the SQL or CALL statement with actual parameters
    - Format as: ```sql  -- step_name\n CALL ...\n```
    - Include output table references so the user can query results directly
    
    ASYNC EXECUTION AWARENESS:
    - DE analysis and pathway enrichment may take 30+ seconds
    - Tell the user the operation is running and provide the output table name
    - Offer: SELECT * FROM {output_table} to check results

tools:
  - tool_spec:
      type: generic
      name: run_differential_expression
      description: "Compare gene expression between two patient groups using Mann-Whitney U test with BH-FDR correction. Returns genes with log2FC, p-values, and direction."
  - tool_spec:
      type: generic
      name: run_pathway_enrichment
      description: "Over-representation analysis of DE genes against MSigDB Hallmark gene sets using Fisher exact test."
  - tool_spec:
      type: generic
      name: run_survival_analysis
      description: "Kaplan-Meier survival analysis with log-rank test and Cox proportional hazards, stratified by a clinical variable."
  - tool_spec:
      type: generic
      name: validate_gene_symbol
      description: "Validate gene symbols against HGNC. Returns approved symbol, name, aliases, and previous symbols."
  - tool_spec:
      type: generic
      name: run_evo2
      description: "Generate DNA/RNA sequences from a prompt sequence using Evo2 NIM. For regulatory element design, codon optimization, or sequence extension."

tool_resources:
  run_differential_expression:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_DIFFERENTIAL_EXPRESSION"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_pathway_enrichment:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_PATHWAY_ENRICHMENT"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_survival_analysis:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_SURVIVAL_ANALYSIS"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  validate_gene_symbol:
    type: function
    name: "SCIENTIFIC_WORKBENCH.CATALOG.VALIDATE_GENE_SYMBOL"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_evo2:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_EVO2"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
$$;
