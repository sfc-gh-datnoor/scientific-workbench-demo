-- =============================================================================
-- engine/sql/create_workflow_runner.sql
-- Cortex Agent definition and workflow status view
-- Run after: setup/08-workflow-engine.sql, all semantic views deployed
-- Requires: CREATE AGENT privilege on SCIENTIFIC_WORKBENCH.CATALOG schema
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;

-- =============================================================================
-- Discovery Agent (main conversational agent with semantic views + search)
-- =============================================================================

CREATE OR REPLACE AGENT SCIENTIFIC_WORKBENCH.CATALOG.DISCOVERY_AGENT
  COMMENT = 'Scientific discovery agent for life sciences R&D — with tool execution'
  PROFILE = '{"display_name": "Scientific Discovery Agent", "avatar": "microscope", "color": "blue"}'
  FROM SPECIFICATION
$$
models:
  orchestration: "claude-sonnet-5-5"

orchestration:
  tool_not_accessible: accept
  budget:
    seconds: 180
    tokens: 64000

instructions:
  response: |
    You are a scientific AI assistant for life sciences R&D. You help researchers
    from 6 roles: Computational Biologist, Medicinal Chemist, Clinical Data Scientist,
    Structural Biologist, Translational Scientist, and AI Drug Discovery Scientist.
    Ground answers in data. Cite sources with specific table/dataset names.
    Label claims as GROUNDED (from data), INFERRED (logical conclusion), or SPECULATIVE (hypothesis).
    Never fabricate p-values, molecule structures, or citations.

    When you execute a tool or workflow, always tell the user:
    1. Which tool you are using and why
    2. What parameters you are passing
    3. A summary of the results with key metrics highlighted
  orchestration: |
    For gene expression or patient cohort questions, use the genomics_analyst tool.
    For compound potency, IC50, or drug-likeness questions, use the compounds_analyst tool.
    For clinical outcomes, response rates, or trial questions, use the clinical_analyst tool.
    For finding tools or datasets, use the search tools.

    TOOL EXECUTION:
    When the user asks to RUN a specific tool (e.g. GenMol, DiffDock, Boltz2) or a multi-step workflow/pipeline:
    1. Use tool_search to confirm the tool exists
    2. Tell the user which tool and what parameters you will send
    3. Delegate the execution to the scientific_tools agent — it routes to the correct domain agent automatically
    4. Interpret the results

    Use code_execution only for Python data analysis, transformation, and visualization — not for CALL statements or procedure execution.
  sample_questions:
    - question: "What is the response rate for KRAS G12C patients on Sotorasib?"
    - question: "Which compounds have the best IC50 against KRAS_G12C?"
    - question: "Run the drug discovery pipeline starting from aspirin"
    - question: "Design a protein binder for PD-L1"
    - question: "Run the target-to-structure workflow on the gene expression data"
    - question: "What workflows are available?"
    - question: "Run GenMol to generate 10 analogs of imatinib"

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "genomics_analyst"
      description: "Query gene expression and patient cohort data. Use for expression levels, patient counts, response rates, survival, and comparisons across treatment arms or mutation groups."
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "compounds_analyst"
      description: "Query compound library and IC50 assay data. Use for potency comparisons, selectivity profiles, drug-likeness properties, and project-level summaries."
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "clinical_analyst"
      description: "Query clinical outcomes and trial registry data. Use for response rates, PFS, patient demographics, and trial phase/status summaries."
  - tool_spec:
      type: "cortex_search"
      name: "tool_search"
      description: "Search the tool registry for available analytical and NIM tools by name or capability. Returns tool names, descriptions, domains, and input parameters."
  - tool_spec:
      type: "cortex_search"
      name: "asset_search"
      description: "Search all registered platform assets including datasets, tools, and experiments."
  - tool_spec:
      type: "data_to_chart"
      name: "data_to_chart"
      description: "Generates visualizations from data returned by other tools."
  - tool_spec:
      type: agent_toolset
      name: scientific_tools
      description: "Execute scientific tools and multi-step pipelines: molecule generation (GenMol), optimization (MolMIM), docking (DiffDock), affinity (Boltz2), protein structure (OpenFold2/3), backbone design (RFdiffusion), inverse folding (ProteinMPNN), DNA generation (Evo2), MSA search, and user-added custom tools. Routes automatically to the correct domain agent."
  - tool_spec:
      type: "code_execution"
      name: "code_execution"
      description: "Execute Python code to process data, perform calculations, transform results, or produce visualizations. Do NOT use this for CALL statements."

tool_resources:
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
  clinical_analyst:
    semantic_view: "SCIENTIFIC_WORKBENCH.CATALOG.SV_CLINICAL"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  tool_search:
    search_service: "SCIENTIFIC_WORKBENCH.CATALOG.TOOL_SEARCH"
    max_results: "5"
  asset_search:
    search_service: "SCIENTIFIC_WORKBENCH.CATALOG.ASSET_SEARCH"
    max_results: "5"
  scientific_tools:
    agent_name: SCIENTIFIC_WORKBENCH.CATALOG.SCIENTIFIC_WORKBENCH_ROUTER
  code_execution:
    permission_policy:
      type: always_allow
$$;

-- Grant usage to workbench roles
GRANT USAGE ON AGENT SCIENTIFIC_WORKBENCH.CATALOG.DISCOVERY_AGENT TO ROLE WORKBENCH_ADMIN;
GRANT USAGE ON AGENT SCIENTIFIC_WORKBENCH.CATALOG.DISCOVERY_AGENT TO ROLE WORKBENCH_SCIENTIST;

-- =============================================================================
-- Workflow status view (useful for app UI)
-- =============================================================================

USE SCHEMA WORKFLOWS;

CREATE OR REPLACE VIEW WORKFLOWS.RUN_STATUS AS
SELECT
    r.run_id,
    t.display_name    AS template_name,
    r.status,
    r.current_step,
    ARRAY_SIZE(t.steps) AS total_steps,
    r.started_at,
    r.completed_at,
    DATEDIFF('second', r.started_at, COALESCE(r.completed_at, CURRENT_TIMESTAMP())) AS elapsed_seconds,
    r.user_name,
    r.agent_summary
FROM WORKFLOWS.RUNS r
JOIN WORKFLOWS.TEMPLATES t ON r.template_id = t.template_id
ORDER BY r.started_at DESC;
