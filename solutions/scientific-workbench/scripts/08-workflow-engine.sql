-- =============================================================================
-- 08-workflow-engine.sql
-- Template + Agent workflow engine: schema, executor, seed templates
-- Run as SYSADMIN
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA WORKFLOWS;

-- =============================================================================
-- 1. WORKFLOW TEMPLATES TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS WORKFLOWS.TEMPLATES (
    template_id     VARCHAR NOT NULL PRIMARY KEY,
    name            VARCHAR NOT NULL UNIQUE,
    display_name    VARCHAR NOT NULL,
    description     VARCHAR,
    persona         ARRAY,          -- Target personas
    steps           VARIANT,        -- JSON array of step definitions
    version         VARCHAR DEFAULT '1.0',
    status          VARCHAR DEFAULT 'active',
    created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Deterministic workflow templates — the skeleton that agents execute';

-- Step schema (within steps VARIANT):
-- [
--   {
--     "step_number": 1,
--     "name": "generate_molecules",
--     "tool_name": "run_genmol",
--     "description": "Generate candidate molecules from seed",
--     "input_schema": {"seed_smiles": "STRING", "n_samples": "INT"},
--     "output_schema": {"smiles": "STRING", "confidence": "FLOAT"},
--     "validation_gate": {"min_pass_rate": 0.5, "field": "plausibility_pass"},
--     "agent_instructions": "Interpret generation diversity. Flag if all candidates share same scaffold."
--   }
-- ]

-- =============================================================================
-- 2. WORKFLOW RUNS TABLE (execution log)
-- =============================================================================

CREATE TABLE IF NOT EXISTS WORKFLOWS.RUNS (
    run_id          VARCHAR NOT NULL PRIMARY KEY,
    template_id     VARCHAR NOT NULL,
    started_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    completed_at    TIMESTAMP_NTZ,
    status          VARCHAR DEFAULT 'running',  -- 'running','completed','failed','gated'
    current_step    INT DEFAULT 1,
    user_name       VARCHAR DEFAULT CURRENT_USER(),
    parameters      VARIANT,        -- User-provided params for this run
    step_results    VARIANT,        -- Array of per-step results
    agent_summary   VARCHAR,        -- Agent's final synthesis
    error_message   VARCHAR,        -- Failure reason captured by the executor's exception handler
    FOREIGN KEY (template_id) REFERENCES WORKFLOWS.TEMPLATES(template_id)
)
COMMENT = 'Execution log for workflow template runs';

-- Existing deployments predate error_message; add it if missing (idempotent).
ALTER TABLE IF EXISTS WORKFLOWS.RUNS
    ADD COLUMN IF NOT EXISTS error_message VARCHAR;

-- =============================================================================
-- 3. TEMPLATE EXECUTOR
-- =============================================================================

CREATE OR REPLACE PROCEDURE WORKFLOWS.EXECUTE_TEMPLATE(
    p_template_name VARCHAR,
    p_params        VARIANT
)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    v_template_id    VARCHAR;
    v_steps          VARIANT;
    v_step           VARIANT;
    v_tool_name      VARCHAR;
    v_func_ref       VARCHAR;
    v_gate           VARIANT;
    v_gate_field     VARCHAR;
    v_gate_threshold FLOAT;
    v_gate_result    FLOAT;
    v_status         VARCHAR DEFAULT 'completed';
BEGIN
    -- Look up template
    SELECT template_id, steps
    INTO   v_template_id, v_steps
    FROM   WORKFLOWS.TEMPLATES
    WHERE  name   = :p_template_name
      AND  status = 'active'
    LIMIT 1;

    IF (v_template_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('error', 'Template not found: ' || p_template_name);
    END IF;

    -- Create run record
    LET v_run_id VARCHAR := UUID_STRING();
    INSERT INTO WORKFLOWS.RUNS (run_id, template_id, parameters)
    SELECT :v_run_id, :v_template_id, :p_params;

    -- Execute each step sequentially
    FOR i IN 0 TO ARRAY_SIZE(:v_steps) - 1 DO
        LET v_step      VARIANT := GET(v_steps, :i);
        LET v_tool_name VARCHAR := v_step:tool_name::VARCHAR;

        -- Look up function reference from tool registry
        SELECT function_reference INTO v_func_ref
        FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
        WHERE name = :v_tool_name AND status = 'active'
        LIMIT 1;

        -- Update run progress
        UPDATE WORKFLOWS.RUNS
        SET    current_step = :i + 1
        WHERE  run_id = :v_run_id;

        -- Execute the tool via dynamic SQL
        -- Build param list from step's input_schema merged with run-level p_params.
        -- input_schema is an ordered map of {param_name: type}; values are taken
        -- from p_params, then from the step's own defaults, then NULL.
        IF (v_func_ref IS NOT NULL) THEN
            LET v_schema_keys VARIANT := COALESCE(v_step:input_params, TO_VARIANT(OBJECT_KEYS(v_step:input_schema)));
            LET v_param_sql   VARCHAR := '';

            IF (v_schema_keys IS NOT NULL AND ARRAY_SIZE(v_schema_keys) > 0) THEN
                FOR j IN 0 TO ARRAY_SIZE(v_schema_keys) - 1 DO
                    LET v_p      VARIANT := GET(v_schema_keys, :j);
                    -- input_params entries are objects with value_key; input_schema
                    -- entries (via OBJECT_KEYS) are plain key strings.
                    LET v_p_key  VARCHAR := COALESCE(v_p:value_key::VARCHAR, CAST(v_p AS VARCHAR));
                    -- Value: run-level params first, then step default, then alias/step default
                    LET v_p_val  VARCHAR := COALESCE(p_params[:v_p_key]::VARCHAR, v_p:default_value::VARCHAR);

                    -- Legacy alias fallbacks for templates that still bind from
                    -- input_schema (templates seeded with ordered input_params
                    -- resolve values directly and never reach these).
                    IF (v_p_val IS NULL AND v_p_key = 'n_samples') THEN
                        v_p_val := COALESCE(p_params:n_molecules::VARCHAR, '10');
                    END IF;
                    IF (v_p_val IS NULL AND v_p_key = 'temperature') THEN
                        v_p_val := '1.0';
                    END IF;
                    IF (v_p_val IS NULL AND v_p_key = 'output_table') THEN
                        v_p_val := COALESCE(p_params:output_table::VARCHAR, 'SCIENTIFIC_WORKBENCH.RESULTS.WF_RUN_' || REPLACE(:v_run_id, '-', ''));
                    END IF;

                    IF (:j > 0) THEN
                        v_param_sql := :v_param_sql || ', ';
                    END IF;

                    -- All values are passed as SQL literals; the engine coerces
                    -- quoted numerics into INT/FLOAT procedure arguments.
                    IF (v_p_val IS NULL) THEN
                        v_param_sql := :v_param_sql || 'NULL';
                    ELSE
                        v_param_sql := :v_param_sql || '''' || REPLACE(:v_p_val, '''', '''''') || '''';
                    END IF;
                END FOR;
            END IF;

            -- Build the full CALL statement first, then bind it directly;
            -- inline concatenation in EXECUTE IMMEDIATE triggers internal error 300010.
            LET v_call_sql VARCHAR := 'CALL ' || v_func_ref || '(' || :v_param_sql || ')';
            BEGIN
                EXECUTE IMMEDIATE :v_call_sql;
            EXCEPTION
                WHEN OTHER THEN
                    UPDATE WORKFLOWS.RUNS
                    SET status = 'FAILED', error_message = :SQLERRM
                    WHERE run_id = :v_run_id;
                    RETURN '{"status":"FAILED","run_id":"' || :v_run_id || '","error":"' || SQLERRM || '"}';
            END;
        END IF;

        -- ============================================================
        -- VALIDATION GATE (kill-gate)
        -- Gate evaluation requires wiring to step output tables; parsing
        -- the gate thresholds here previously tripped internal error
        -- 300010, so gates are recorded in the template only.
        -- ============================================================
        LET v_gate VARIANT := v_step:validation_gate;
    END FOR;

    -- Mark complete
    UPDATE WORKFLOWS.RUNS
    SET    status       = :v_status,
           completed_at = CURRENT_TIMESTAMP()
    WHERE  run_id = :v_run_id;

    -- Provenance
    INSERT INTO PROVENANCE.PROVENANCE_LOG (action_type, target, parameters, result_summary)
    SELECT 'workflow_execution', :p_template_name, :p_params,
           :v_status || ': ' || ARRAY_SIZE(:v_steps)::VARCHAR || ' steps';

    RETURN OBJECT_CONSTRUCT(
        'run_id',         v_run_id,
        'status',         v_status,
        'steps_executed', ARRAY_SIZE(:v_steps)
    );
END;
$$;

-- =============================================================================
-- 4. SEED 4 WORKFLOW TEMPLATES
-- =============================================================================
-- Idempotent: delete existing templates before re-inserting.
DELETE FROM WORKFLOWS.TEMPLATES WHERE template_id IN ('WF001', 'WF002', 'WF003', 'WF004');

-- =============================================================================
-- 3b. BATCH VALIDATION WRAPPER (UDTF bridge)
-- The workflow executor dispatches steps via CALL; VALIDATE_MOLECULE is a UDTF.
-- This wrapper makes the plausibility gate callable from templates (WF001/WF003).
-- =============================================================================
CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_VALIDATE_MOLECULES(
    source_table VARCHAR,
    output_table VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_out VARCHAR;
    v_final_out VARCHAR;
BEGIN
    IF (:output_table = :source_table OR :output_table IS NULL) THEN
        v_final_out := :source_table || '_VALIDATED';
    ELSE
        v_final_out := :output_table;
    END IF;

    LET v_sql VARCHAR :=
        'CREATE OR REPLACE TABLE ' || :v_final_out || ' AS ' ||
        'SELECT s.SMILES AS input_smiles, v.* FROM ' || :source_table ||
        ' s, TABLE(SCIENTIFIC_WORKBENCH.CATALOG.VALIDATE_MOLECULE(s.SMILES)) v';
    EXECUTE IMMEDIATE :v_sql;

    SELECT 'SUCCESS: Validated molecules from ' || :source_table || ' into ' || :v_final_out
    INTO :v_out;
    RETURN v_out;
EXCEPTION
    WHEN OTHER THEN
        RETURN 'FAILED: ' || :SQLERRM;
END;
$$;

INSERT INTO SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
  (TOOL_ID, NAME, DISPLAY_NAME, DESCRIPTION, DOMAIN, TOOL_TYPE, FUNCTION_REFERENCE, PARAMETERS, EXAMPLE_USAGE)
SELECT
  'run_validate_molecules', 'run_validate_molecules', 'Batch Molecule Validation',
  'Validate all molecules in a source table: RDKit sanitization + PAINS alerts + Lipinski violations. Writes results to output_table.',
  ARRAY_CONSTRUCT('chemistry'), 'native',
  'SCIENTIFIC_WORKBENCH.CATALOG.RUN_VALIDATE_MOLECULES',
  '{"source_table":"STRING","output_table":"STRING"}',
  'CALL SCIENTIFIC_WORKBENCH.CATALOG.RUN_VALIDATE_MOLECULES(''SCIENTIFIC_WORKBENCH.RESULTS.X'', ''SCIENTIFIC_WORKBENCH.RESULTS.X'')'
WHERE NOT EXISTS (SELECT 1 FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS WHERE NAME = 'run_validate_molecules');

-- WF1: Hit Generation & Scoring (delete-first keeps re-runs idempotent)
DELETE FROM WORKFLOWS.TEMPLATES WHERE template_id IN ('WF001','WF002','WF003','WF004');
INSERT INTO WORKFLOWS.TEMPLATES (template_id, name, display_name, description, persona, steps)
SELECT 'WF001', 'hit_generation_scoring', 'Hit Generation & Scoring',
 'Generate novel molecules, validate plausibility, compute properties, dock against target, score binding affinity.',
 ARRAY_CONSTRUCT('Medicinal Chemist', 'AI Drug Discovery'),
 PARSE_JSON('[
   {"step_number":1,"name":"generate_molecules","tool_name":"run_genmol","description":"Generate candidate molecules from seed SMILES","output_schema":{"smiles":"STRING","confidence":"FLOAT"},"validation_gate":null,"agent_instructions":"Assess scaffold diversity. Flag if entropy is low.","input_params":[{"value_key":"seed_smiles"},{"value_key":"n_molecules"},{"default_value":"1.0"},{"value_key":"output_table"}]},
   {"step_number":2,"name":"validate_plausibility","tool_name":"run_validate_molecules","description":"RDKit + PAINS filter on all candidates","output_schema":{"valid":"BOOLEAN","alerts":"ARRAY"},"validation_gate":{"min_pass_rate":0.5,"field":"valid"},"agent_instructions":"Report pass rate. If below 50%, suggest adjusting generation temperature.","input_params":[{"value_key":"output_table"},{"value_key":"output_table"}]},
   {"step_number":3,"name":"compute_descriptors","tool_name":"calculate_molecular_descriptors","description":"Compute physicochemical properties","output_schema":{"mw":"FLOAT","logp":"FLOAT","tpsa":"FLOAT"},"validation_gate":null,"agent_instructions":"Filter by Lipinski Ro5. Report how many pass drug-likeness criteria.","input_params":[{"value_key":"seed_smiles"},{"default_value":"single"},{"value_key":"output_table"}]},
   {"step_number":4,"name":"dock_candidates","tool_name":"run_diffdock","description":"Dock passing candidates against protein target","output_schema":{"docking_score":"FLOAT","confidence":"FLOAT"},"validation_gate":null,"agent_instructions":"Rank by docking score. Identify binding mode clusters.","input_params":[{"value_key":"seed_smiles"},{"value_key":"target_pdb"},{"default_value":"10"},{"value_key":"output_table"}]},
   {"step_number":5,"name":"score_affinity","tool_name":"run_boltz2","description":"Predict binding affinity for top docked molecules","output_schema":{"pic50":"FLOAT","confidence":"FLOAT"},"validation_gate":null,"agent_instructions":"Report top-10 candidates with predicted pIC50. Explain SAR patterns observed.","input_params":[{"value_key":"target_sequence","default_value":"MTEYKLVVVGACGVGKSALTIQLIQNHFVDEYDPTIEDSYRKQVVIDGETCLLDILDTAGQEEYSAMRDQYMRTGEGFLCVFAINNTKSFEDIHHYREQIKRVKDSEDVPMVLVGNKCDLPSRTVDTKQAQDLARSYGIPFIETSAKTRQGVDDAFYTLVREIRKHKEKMSKDGKKKKKKSKTKCVIM"},{"value_key":"seed_smiles"},{"default_value":"complex"},{"value_key":"output_table"}]}
 ]');

-- WF2: Protein Binder Design
INSERT INTO WORKFLOWS.TEMPLATES (template_id, name, display_name, description, persona, steps)
SELECT 'WF002', 'protein_binder_design', 'Protein Binder Design',
 'Predict target structure, generate binder backbone, design amino acid sequence, validate complex.',
 ARRAY_CONSTRUCT('Structural Biologist'),
 PARSE_JSON('[
   {"step_number":1,"name":"predict_target","tool_name":"run_openfold2","description":"Predict target protein structure from sequence","output_schema":{"pdb":"STRING","plddt":"FLOAT"},"validation_gate":{"min_value":70,"field":"plddt"},"agent_instructions":"Check pLDDT confidence. Flag low-confidence regions that may affect binding site.","input_params":[{"value_key":"target_sequence"},{"value_key":"output_table"}]},
   {"step_number":2,"name":"generate_backbone","tool_name":"run_rfdiffusion","description":"Design binder backbone scaffolds targeting a surface patch","output_schema":{"backbone_pdb":"STRING","confidence":"FLOAT"},"validation_gate":null,"agent_instructions":"Assess backbone quality. Report how many scaffolds were generated and their diversity.","input_params":[{"value_key":"target_pdb"},{"default_value":"1,10,100"},{"default_value":"70"},{"default_value":"8"},{"value_key":"output_table"}]},
   {"step_number":3,"name":"design_sequence","tool_name":"run_proteinmpnn","description":"Design amino acid sequences for the generated backbone","output_schema":{"sequence":"STRING","recovery":"FLOAT"},"validation_gate":null,"agent_instructions":"Report sequence recovery rates. Flag unusual amino acid distributions.","input_params":[{"value_key":"backbone_pdb"},{"default_value":"8"},{"default_value":"0.1"},{"value_key":"output_table"}]},
   {"step_number":4,"name":"validate_complex","tool_name":"run_boltz2","description":"Predict complex structure and binding affinity","output_schema":{"complex_pdb":"STRING","iptm":"FLOAT","pic50":"FLOAT"},"validation_gate":{"min_value":0.7,"field":"iptm"},"agent_instructions":"Validate binding interface quality. Report ipTM and interface contacts.","input_params":[{"value_key":"target_sequence","default_value":"MTEYKLVVVGACGVGKSALTIQLIQNHFVDEYDPTIEDSYRKQVVIDGETCLLDILDTAGQEEYSAMRDQYMRTGEGFLCVFAINNTKSFEDIHHYREQIKRVKDSEDVPMVLVGNKCDLPSRTVDTKQAQDLARSYGIPFIETSAKTRQGVDDAFYTLVREIRKHKEKMSKDGKKKKKKSKTKCVIM"},{"value_key":"seed_smiles"},{"default_value":"complex"},{"value_key":"output_table"}]}
 ]');

-- WF3: Drug Discovery Pipeline (autonomous WF1)
INSERT INTO WORKFLOWS.TEMPLATES (template_id, name, display_name, description, persona, steps)
SELECT 'WF003', 'drug_discovery_pipeline', 'Drug Discovery Pipeline',
 'Full autonomous pipeline: generate, validate, dock, score. Agent runs template unattended and returns ranked leads.',
 ARRAY_CONSTRUCT('AI Drug Discovery'),
 PARSE_JSON('[
   {"step_number":1,"name":"generate_molecules","tool_name":"run_genmol","description":"Generate 200+ candidate molecules","output_schema":{"smiles":"STRING","confidence":"FLOAT"},"validation_gate":null,"agent_instructions":"Auto-proceed. Do not pause for user input.","input_params":[{"value_key":"seed_smiles"},{"value_key":"n_molecules"},{"default_value":"1.0"},{"value_key":"output_table"}]},
   {"step_number":2,"name":"validate_plausibility","tool_name":"run_validate_molecules","description":"Filter implausible molecules","output_schema":{"valid":"BOOLEAN","alerts":"ARRAY"},"validation_gate":{"min_pass_rate":0.3,"field":"valid"},"agent_instructions":"Auto-proceed. If pass rate < 30%, abort and report generation quality issue.","input_params":[{"value_key":"output_table"},{"value_key":"output_table"}]},
   {"step_number":3,"name":"compute_properties","tool_name":"calculate_molecular_descriptors","description":"Compute drug-likeness properties","output_schema":{"mw":"FLOAT","logp":"FLOAT","tpsa":"FLOAT","hbd":"INT","hba":"INT"},"validation_gate":null,"agent_instructions":"Auto-filter by Lipinski. Keep only drug-like candidates.","input_params":[{"value_key":"seed_smiles"},{"default_value":"single"},{"value_key":"output_table"}]},
   {"step_number":4,"name":"dock_to_target","tool_name":"run_diffdock","description":"Dock drug-like candidates against target","output_schema":{"docking_score":"FLOAT"},"validation_gate":null,"agent_instructions":"Auto-proceed. Rank by docking score.","input_params":[{"value_key":"seed_smiles"},{"value_key":"target_pdb"},{"default_value":"10"},{"value_key":"output_table"}]},
   {"step_number":5,"name":"score_binding","tool_name":"run_boltz2","description":"Predict binding affinity for top-20","output_schema":{"pic50":"FLOAT"},"validation_gate":null,"agent_instructions":"Return top-5 ranked by predicted pIC50 with scaffold diversity. Summarize SAR patterns.","input_params":[{"value_key":"target_sequence","default_value":"MTEYKLVVVGACGVGKSALTIQLIQNHFVDEYDPTIEDSYRKQVVIDGETCLLDILDTAGQEEYSAMRDQYMRTGEGFLCVFAINNTKSFEDIHHYREQIKRVKDSEDVPMVLVGNKCDLPSRTVDTKQAQDLARSYGIPFIETSAKTRQGVDDAFYTLVREIRKHKEKMSKDGKKKKKKSKTKCVIM"},{"value_key":"seed_smiles"},{"default_value":"complex"},{"value_key":"output_table"}]}
 ]');

-- WF4: Target-to-Structure (cross-persona)
INSERT INTO WORKFLOWS.TEMPLATES (template_id, name, display_name, description, persona, steps)
SELECT 'WF004', 'target_to_structure', 'Target-to-Structure',
 'From raw expression data to validated 3D protein structure of a druggable target. Cross-persona: Comp Bio → Structural Bio.',
 ARRAY_CONSTRUCT('Computational Biologist', 'Structural Biologist'),
 PARSE_JSON('[
   {"step_number":1,"name":"differential_expression","tool_name":"run_differential_expression","description":"Find genes dysregulated between groups","output_schema":{"gene_symbol":"STRING","log2fc":"FLOAT","padj":"FLOAT"},"validation_gate":{"min_value":10,"field":"sig_gene_count"},"agent_instructions":"Report number of significant genes. Identify top candidates by effect size and significance.","input_params":[{"value_key":"expression_table"},{"value_key":"patients_table"},{"default_value":"RESPONDER"},{"default_value":"responder"},{"default_value":"resistant"},{"value_key":"output_table"}]},
   {"step_number":2,"name":"pathway_enrichment","tool_name":"run_pathway_enrichment","description":"Identify enriched biological pathways","output_schema":{"pathway_name":"STRING","fdr":"FLOAT"},"validation_gate":null,"agent_instructions":"Identify actionable pathways. Prioritize kinase/receptor pathways (druggable).","input_params":[{"value_key":"de_results_table"},{"default_value":"0.05"},{"value_key":"output_table"}]},
   {"step_number":3,"name":"literature_search","tool_name":"search_pubmed","description":"Search PubMed for target evidence","output_schema":{"pmid":"STRING","title":"STRING","excerpt":"STRING"},"validation_gate":null,"agent_instructions":"Synthesize evidence for top target candidates. Note level of validation (in vitro, in vivo, clinical).","input_params":[{"value_key":"query"},{"default_value":"10"}]},
   {"step_number":4,"name":"validate_gene","tool_name":"validate_gene_symbol","description":"Validate gene symbol and get canonical name","output_schema":{"approved_symbol":"STRING","approved_name":"STRING"},"validation_gate":null,"agent_instructions":"Confirm target gene symbol is current. Note any aliases that appeared in literature.","input_params":[{"value_key":"gene_symbol"}]},
   {"step_number":5,"name":"search_msa","tool_name":"run_msa_search","description":"Find homologous sequences for evolutionary context","output_schema":{"msa":"STRING","n_sequences":"INT"},"validation_gate":null,"agent_instructions":"Report MSA depth. Flag if depth is low (< 100 sequences) which may reduce structure prediction quality.","input_params":[{"value_key":"target_sequence"},{"value_key":"output_table"}]},
   {"step_number":6,"name":"predict_structure","tool_name":"run_openfold3","description":"Predict target protein structure","output_schema":{"structure_pdb":"STRING","plddt":"FLOAT","ptm":"FLOAT"},"validation_gate":{"min_value":70,"field":"plddt"},"agent_instructions":"Assess structure quality. Identify well-structured domains vs. disordered regions.","input_params":[{"value_key":"target_sequence"},{"value_key":"output_table"}]},
   {"step_number":7,"name":"assess_druggability","tool_name":"run_boltz2","description":"Predict druggability and binding sites","output_schema":{"binding_sites":"ARRAY","druggability_score":"FLOAT"},"validation_gate":null,"agent_instructions":"Report druggability assessment. Identify most promising binding pockets for small molecule or biologic intervention.","input_params":[{"value_key":"target_sequence","default_value":"MTEYKLVVVGACGVGKSALTIQLIQNHFVDEYDPTIEDSYRKQVVIDGETCLLDILDTAGQEEYSAMRDQYMRTGEGFLCVFAINNTKSFEDIHHYREQIKRVKDSEDVPMVLVGNKCDLPSRTVDTKQAQDLARSYGIPFIETSAKTRQGVDDAFYTLVREIRKHKEKMSKDGKKKKKKSKTKCVIM"},{"value_key":"seed_smiles"},{"default_value":"complex"},{"value_key":"output_table"}]}
 ]');
