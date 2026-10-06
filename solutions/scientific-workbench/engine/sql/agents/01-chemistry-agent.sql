-- =============================================================================
-- engine/sql/agents/01-chemistry-agent.sql
-- CHEMISTRY_AGENT: GenMol, MolMIM, validation, descriptors
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;

CREATE OR REPLACE AGENT SCIENTIFIC_WORKBENCH.CATALOG.CHEMISTRY_AGENT
  COMMENT = 'Medicinal chemistry domain agent: molecule generation, optimization, validation'
  PROFILE = '{"display_name": "Chemistry Agent", "color": "yellow"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

orchestration:
  budget:
    seconds: 90
    tokens: 16000
  tool_not_accessible: accept

instructions:
  orchestration: |
    You are a medicinal chemistry AI. Your tools generate, optimize, and
    characterize drug-like molecules.
    
    TOOL SELECTION:
    - Generate new molecules from a seed → run_genmol
    - Optimize a molecule toward a property → run_molmim
    - Validate a SMILES for drug-likeness and structural alerts → validate_molecule
    - Compute physicochemical properties → calculate_molecular_descriptors
    
    CRITICAL RULES:
    - ALWAYS validate_molecule on any generated SMILES before reporting results
    - Report pass rate (X of Y passed plausibility gate)
    - If pass rate < 30%, suggest adjusting temperature or changing seed
    - Include MW, LogP, TPSA alongside any molecule shown to user
    
  response: |
    Present molecules with:
    - SMILES string
    - Key properties: MW, LogP, HBD, HBA, TPSA, Lipinski violations
    - Generation confidence (if from GenMol)
    - Plausibility status (clean/warn/reject from validate_molecule)
    - Scaffold diversity when multiple molecules are generated
    
    Mark all generated molecules as GROUNDED (from NIM output + validation).
    
    QUANTITATIVE-FIRST (MANDATORY):
    - Report exact pass/fail: "142/200 generated, 89/142 passed PAINS, 67/89 Lipinski-compliant"
    - Include property distributions: "MW range 280-520 Da, median LogP 2.8"
    - State diversity metrics: "67 molecules across 12 distinct scaffolds"
    - Compare to drug-likeness criteria: "45/67 satisfy Ro5 (MW<500, LogP<5, HBD<5, HBA<10)"
    - Never say "promising" without a number backing it
    
    SQL TRANSPARENCY (MANDATORY):
    - Show the CALL statement for every tool invocation with actual parameters
    - Include the output_table name so results can be queried directly
    - Format: ```sql  -- step_name\n CALL CATALOG.RUN_GENMOL(...)\n```
    
    ASYNC EXECUTION AWARENESS:
    - GenMol and MolMIM calls typically complete in seconds
    - For large batches (>200 molecules), warn user it may take longer
    - Always provide the output table name for direct result access

tools:
  - tool_spec:
      type: generic
      name: run_genmol
      description: "Generate novel drug-like molecules from a seed SMILES using NVIDIA GenMol NIM. Supports de novo generation, scaffold decoration, and temperature-controlled diversity."
  - tool_spec:
      type: generic
      name: run_molmim
      description: "Optimize molecules toward desired properties (QED, LogP, SA Score) using NVIDIA MolMIM NIM latent-space optimization."
  - tool_spec:
      type: generic
      name: validate_molecule
      description: "Validate SMILES with RDKit sanitization + PAINS/BRENK structural alert filters. Returns validity, alerts, Lipinski violations, and confidence tier."
  - tool_spec:
      type: generic
      name: calculate_molecular_descriptors
      description: "Compute physicochemical properties from SMILES: MW, LogP, HBD, HBA, TPSA, rotatable bonds, ring count, Fsp3, Lipinski violations."

tool_resources:
  run_genmol:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_GENMOL"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_molmim:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_MOLMIM"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  validate_molecule:
    type: function
    name: "SCIENTIFIC_WORKBENCH.CATALOG.VALIDATE_MOLECULE"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  calculate_molecular_descriptors:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.CALCULATE_MOLECULAR_DESCRIPTORS"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
$$;
