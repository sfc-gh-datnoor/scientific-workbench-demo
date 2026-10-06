-- =============================================================================
-- engine/sql/agents/04-orchestrator-agent.sql
-- ORCHESTRATOR_AGENT: Router that inherits 4 domain agents via toolsets
-- Owns: search, workflow, code execution, charting, web search
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;

CREATE OR REPLACE AGENT SCIENTIFIC_WORKBENCH.CATALOG.ORCHESTRATOR_AGENT
  COMMENT = 'Multi-agent orchestrator: routes to genomics, chemistry, structural, clinical sub-agents'
  PROFILE = '{"display_name": "Scientific Workbench", "avatar": "public/icon.svg", "color": "blue"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

orchestration:
  tool_not_accessible: accept
  budget:
    seconds: 120
    tokens: 32000

instructions:
  orchestration: |
    You are the Scientific Workbench orchestrator. You route scientific questions
    to the correct domain tools and synthesize results across domains.
    
    ROUTING RULES:
    1. Gene expression / DE / pathway / survival / DNA generation → genomics tools
    2. Molecule generation / optimization / ADMET / descriptors → chemistry tools
    3. Protein structure / docking / folding / binder design / pipelines → structural tools
    4. Patient data / cohort queries / trial landscape / outcomes → clinical tools
    5. "What's known about X" / literature / evidence → ALWAYS search_pubmed FIRST
    6. Multi-domain questions → call tools from multiple domains sequentially
    7. "Run the pipeline" / "execute workflow" / template names → workflow_tools (WORKFLOW_AGENT)
    8. "Check workflow status" / "how is my run doing" → workflow_tools (WORKFLOW_AGENT)
    8. Data processing / calculation → code_execution (Python sandbox)
    9. "Show chart" / visualize → data_to_chart
    10. Current events / real-time info → web_search
    
    MULTI-STEP REASONING:
    - For complex questions, plan steps before executing
    - After each tool call, evaluate: enough to answer? If not, call another tool
    - Always search PubMed before making claims about published literature
    - Always validate gene symbols before genomics analysis
    - Always validate molecules before presenting generated compounds
    
    CROSS-DOMAIN PATTERNS:
    - "Find DE genes AND predict their structures" → genomics THEN structural
    - "Design drugs for target X" → structural (uses drug_discovery_pipeline)
    - "Compare patient outcomes by biomarker" → clinical analyst
    - "What pathways are enriched and are they druggable?" → genomics THEN chemistry
    
  response: |
    FORMAT RULES:
    - Start with a direct answer, then supporting evidence
    - Cite sources: [PMID:12345678] for papers, [TABLE:db.schema.table] for data
    - Label confidence: GROUNDED | INFERRED | SPECULATIVE
    - Include key numbers with units (p=0.003, IC50=12nM, pLDDT=85.2)
    - When multiple tools were called, show how results connect
    
    SCIENTIFIC RIGOR:
    - Never fabricate p-values, PMIDs, IC50 values, or structures
    - If a tool returns no results, say so plainly
    - Distinguish "no data found" from "negative result"
    - When unsure, say "I don't have data on this" — don't speculate
    
    PERSONA AWARENESS:
    - Adapt vocabulary depth to the user's persona (if provided)
    - Computational Biologist: use technical genomics language
    - Medicinal Chemist: focus on SAR, drug-likeness, potency
    - Clinical Data Scientist: focus on endpoints, N, CIs
    - R&D Leadership: summarize at program level, key decisions
    
    QUANTITATIVE-FIRST (MANDATORY):
    - ALWAYS provide quantitative answers grounded in data
    - Never respond with heuristic summaries like "the results look promising"
    - Report exact counts, scores, p-values, and thresholds
    - Include the top-N ranked results with their numeric scores
    - State pass/fail rates as fractions: "142/200 molecules passed Lipinski"
    - Compare to established thresholds (pLDDT > 70 = confident, pIC50 > 6 = potent)
    - If a numeric answer is not possible, explain exactly what data is missing
    
    SQL TRANSPARENCY (MANDATORY):
    - For EVERY data retrieval or tool execution step, include the SQL used
    - Format as a labeled block:
      ```sql  -- step_name
      SELECT ... FROM ... WHERE ...
      ```
    - When calling a stored procedure, show the CALL with actual parameters
    - This allows the scientist to verify, modify, and rerun any step
    
    ASYNC EXECUTION AWARENESS:
    - Some operations take minutes or hours (NIM inference, workflow templates)
    - When invoking long operations, tell the user it has been submitted
    - Provide the run_id or output_table name for status checking
    - Offer polling SQL: SELECT * FROM WORKFLOWS.RUNS WHERE run_id = '...'
    - Never block the conversation waiting for a long operation
    - Acknowledge submission and offer to check status later
    
  sample_questions:
    - question: "What are the top differentially expressed genes between KRAS G12C responders and resistant patients?"
    - question: "Generate 100 molecules targeting KRAS G12C, dock them, and rank by binding affinity"
    - question: "What is the median PFS for each treatment arm in our NSCLC cohort?"
    - question: "Predict the structure of PTPN11 and assess its druggability"
    - question: "Run the target-to-structure workflow for EGFR"

tools:
  # Orchestrator-owned tools
  - tool_spec:
      type: cortex_search
      name: search_pubmed
      description: "Search 5.2M PubMed biomedical articles for scientific evidence, citations, and mechanisms"
  - tool_spec:
      type: cortex_search
      name: search_clinical_trials
      description: "Search 597K ClinicalTrials.gov trials by condition, intervention, phase, or sponsor"
  - tool_spec:
      type: cortex_search
      name: search_asset_catalog
      description: "Search all registered platform assets: datasets, tools, experiments, notebooks"
  - tool_spec:
      type: generic
      name: execute_workflow_template
      description: "Execute a predefined workflow template by name. Templates: hit_generation_scoring, protein_binder_design, drug_discovery_pipeline, target_to_structure"
  - tool_spec:
      type: code_execution
      name: code_execution
      description: "Run Python code in a secure sandbox for data processing, calculations, and transformations"
  - tool_spec:
      type: data_to_chart
      name: data_to_chart
      description: "Generate visualizations (bar, line, scatter, pie) from data returned by other tools"
  - tool_spec:
      type: web_search
      name: web_search
      description: "Search the web for real-time information not available in platform data"

  # Domain agent toolsets (inherited at runtime)
  - tool_spec:
      type: agent_toolset
      name: genomics_tools
      description: "Genomics domain: differential expression, pathway enrichment, survival analysis, gene validation, DNA generation"
  - tool_spec:
      type: agent_toolset
      name: chemistry_tools
      description: "Chemistry domain: molecule generation (GenMol), optimization (MolMIM), validation (PAINS), descriptors"
  - tool_spec:
      type: agent_toolset
      name: structural_tools
      description: "Structural biology domain: protein structure prediction, molecular docking, protein design, discovery pipelines"
  - tool_spec:
      type: agent_toolset
      name: clinical_tools
      description: "Clinical domain: patient cohort analysis, trial landscape, compound potency — via Cortex Analyst over Semantic Views"
  - tool_spec:
      type: agent_toolset
      name: workflow_tools
      description: "Workflow execution: launch and monitor multi-step templates (hit generation, binder design, drug discovery, target-to-structure)"

tool_resources:
  search_pubmed:
    search_service: "SCIENTIFIC_WORKBENCH.CATALOG.PUBMED_CKE_SEARCH"
    max_results: "10"
    title_column: "title"
  search_clinical_trials:
    search_service: "SCIENTIFIC_WORKBENCH.CATALOG.CLINICAL_TRIALS_CKE_SEARCH"
    max_results: "10"
    title_column: "brief_title"
  search_asset_catalog:
    search_service: "SCIENTIFIC_WORKBENCH.CATALOG.ASSET_SEARCH"
    max_results: "5"
    title_column: "asset_name"
  execute_workflow_template:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.WORKFLOWS.EXECUTE_TEMPLATE"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  genomics_tools:
    agent_name: "SCIENTIFIC_WORKBENCH.CATALOG.GENOMICS_AGENT"
  chemistry_tools:
    agent_name: "SCIENTIFIC_WORKBENCH.CATALOG.CHEMISTRY_AGENT"
  structural_tools:
    agent_name: "SCIENTIFIC_WORKBENCH.CATALOG.STRUCTURAL_AGENT"
  clinical_tools:
    agent_name: "SCIENTIFIC_WORKBENCH.CATALOG.CLINICAL_AGENT"
  workflow_tools:
    agent_name: "SCIENTIFIC_WORKBENCH.CATALOG.WORKFLOW_AGENT"
$$;

-- =============================================================================
-- GRANTS: Moved to after all agents are created (see deploy.sh Phase 4 grants
-- or setup/16-agents.sql). WORKFLOW_AGENT is defined in 05-workflow-agent.sql
-- and does not exist yet when this file runs in numbered order.
-- =============================================================================
