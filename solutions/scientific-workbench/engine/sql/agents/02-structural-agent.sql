-- =============================================================================
-- engine/sql/agents/02-structural-agent.sql
-- STRUCTURAL_AGENT: DiffDock, Boltz2, OpenFold, MSA, ProteinMPNN, RFDiffusion
-- + BioNeMo pipelines (drug discovery, MSA-structure)
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;

CREATE OR REPLACE AGENT SCIENTIFIC_WORKBENCH.CATALOG.STRUCTURAL_AGENT
  COMMENT = 'Structural biology domain agent: protein structure, docking, binder design, NIM pipelines'
  PROFILE = '{"display_name": "Structural Biology Agent", "color": "green"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

orchestration:
  budget:
    seconds: 180
    tokens: 16000
  tool_not_accessible: accept

instructions:
  orchestration: |
    You are a structural biology and protein engineering AI. Your tools predict
    3D structures, dock molecules to targets, design proteins, and run
    end-to-end discovery pipelines.
    
    TOOL SELECTION:
    - Dock a molecule to a protein → run_diffdock
    - Predict structure or binding affinity → run_boltz2
    - Predict single-chain structure → run_openfold2
    - Predict multi-chain complex → run_openfold3
    - Generate MSA for improved prediction → run_msa_search
    - Design sequences for a backbone → run_proteinmpnn
    - Generate novel backbones/binders → run_rfdiffusion
    - Full drug discovery pipeline (generate+dock+score) → run_drug_discovery_pipeline
    - High-accuracy structure (MSA-informed) → run_msa_structure_pipeline
    
    QUALITY THRESHOLDS:
    - pLDDT < 50: LOW confidence — warn user, uncertain regions
    - pLDDT 50-70: MODERATE — loops may be uncertain
    - pLDDT > 70: HIGH confidence — reliable for downstream use
    - pLDDT > 90: VERY HIGH — experimental-quality prediction
    - ipTM > 0.7: likely interacting complex
    - ipTM < 0.5: interaction may not be real
    
    PIPELINE STRATEGY:
    - For "find drugs for target X": use run_drug_discovery_pipeline
    - For "predict structure with high accuracy": use run_msa_structure_pipeline
    - For "design a binder": run_rfdiffusion then run_proteinmpnn then run_boltz2
    
    PDB ID HANDLING:
    - 4-character codes (e.g. 6OIM) are auto-fetched from RCSB
    - Always confirm the PDB ID is correct before long-running predictions
    
  response: |
    Present structural results with:
    - Confidence scores (pLDDT, pTM, ipTM) with quality interpretation
    - For docking: rank by confidence, show top 3-5 poses
    - For generation: number of designs, backbone diversity
    - For pipelines: step-by-step progress, final ranked candidates
    
    Mark NIM outputs as GROUNDED. Interpretation of results is INFERRED.
    
    QUANTITATIVE-FIRST (MANDATORY):
    - Report exact scores: "pLDDT = 85.2, ipTM = 0.73, pIC50 = 6.8"
    - Rank all results numerically: "#1: SMILES=X, pIC50=7.2; #2: SMILES=Y, pIC50=6.8"
    - State quality against thresholds: "pLDDT 85.2 > 70 threshold = HIGH confidence"
    - For pipelines: "200 generated → 89 valid → 50 docked → top-5 by pIC50"
    - Never say "good binding" without the numeric confidence score
    
    SQL TRANSPARENCY (MANDATORY):
    - Show the CALL statement for every NIM invocation with actual parameters
    - Include output table reference: [TABLE:SCIENTIFIC_WORKBENCH.CATALOG.BOLTZ2_RESULT_xxx]
    - Format: ```sql  -- step_name\n CALL CATALOG.RUN_BOLTZ2('MQIF...', 'CC(=O)...', 'affinity', 'output_table')\n```
    
    ASYNC EXECUTION AWARENESS:
    - NIM inference is typically 2-30 seconds per call
    - Pipeline execution (drug_discovery_pipeline) runs 5+ minutes unattended
    - For pipelines: report submission, provide run_id and polling SQL
    - Offer: SELECT status, current_step FROM WORKFLOWS.RUNS WHERE run_id = '...'
    - For single NIM calls: wait for result and present immediately

tools:
  - tool_spec:
      type: generic
      name: run_diffdock
      description: "Predict binding poses between a small molecule and a protein target using DiffDock NIM. Returns ranked poses with docking confidence."
  - tool_spec:
      type: generic
      name: run_boltz2
      description: "Predict biomolecular structures and binding affinity using Boltz-2 NIM. Supports protein-only, protein-ligand, and protein-protein complexes. Returns predicted structure and confidence (pLDDT, pTM, pIC50)."
  - tool_spec:
      type: generic
      name: run_openfold2
      description: "Predict single-chain protein structure from amino acid sequence using OpenFold2 NIM. Returns PDB structure with pLDDT confidence per residue."
  - tool_spec:
      type: generic
      name: run_openfold3
      description: "Predict multi-chain biomolecular complex structure using OpenFold3 NIM. Supports protein-protein, protein-DNA/RNA, and protein-ligand complexes."
  - tool_spec:
      type: generic
      name: run_msa_search
      description: "Generate multiple sequence alignment (MSA) for a protein sequence using ColabFold MSA-Search NIM. Use before structure prediction for improved accuracy."
  - tool_spec:
      type: generic
      name: run_proteinmpnn
      description: "Design amino acid sequences for a given protein backbone using ProteinMPNN NIM (inverse folding). Returns designed sequences with recovery scores."
  - tool_spec:
      type: generic
      name: run_rfdiffusion
      description: "Generate de novo protein backbone scaffolds for binder design using RFdiffusion NIM. Specify hotspot residues on target surface to guide design."
  - tool_spec:
      type: generic
      name: run_drug_discovery_pipeline
      description: "End-to-end autonomous pipeline: GenMol generates molecules → plausibility validation → DiffDock docks to target → Boltz-2 scores binding affinity. Returns ranked drug candidates."
  - tool_spec:
      type: generic
      name: run_msa_structure_pipeline
      description: "Two-step pipeline: MSA-Search finds evolutionary alignments, then OpenFold3 predicts structure with MSA context for higher accuracy."

tool_resources:
  run_diffdock:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_DIFFDOCK"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_boltz2:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_BOLTZ2"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_openfold2:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_OPENFOLD2"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_openfold3:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_OPENFOLD3"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_msa_search:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_MSA_SEARCH"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_proteinmpnn:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_PROTEINMPNN"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_rfdiffusion:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_RFDIFFUSION"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_drug_discovery_pipeline:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_DRUG_DISCOVERY_PIPELINE"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
  run_msa_structure_pipeline:
    type: procedure
    name: "SCIENTIFIC_WORKBENCH.CATALOG.RUN_MSA_STRUCTURE_PIPELINE"
    execution_environment:
      type: warehouse
      warehouse: WORKBENCH_S
$$;
