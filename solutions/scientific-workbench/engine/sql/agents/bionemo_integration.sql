-- =============================================================================
-- engine/sql/agents/bionemo_integration.sql
-- BioNeMo NIM Integration Layer
-- Defines how NVIDIA NIMs are distributed across domain agents and how
-- pipelines chain tools across agent boundaries.
-- =============================================================================
--
-- NVIDIA BioNeMo NIM ↔ Agent Mapping:
--
-- ┌─────────────────────────────────────────────────────────────────────┐
-- │                    NVIDIA BioNeMo NIMs                               │
-- │                                                                     │
-- │  Small Molecule          Protein/Structure          Genomics        │
-- │  ─────────────          ─────────────────          ────────        │
-- │  • GenMol               • DiffDock                 • Evo2          │
-- │  • MolMIM               • Boltz-2                                  │
-- │                          • OpenFold2                                │
-- │       ↓                  • OpenFold3                     ↓         │
-- │                          • MSA-Search                              │
-- │  CHEMISTRY_AGENT         • ProteinMPNN         GENOMICS_AGENT     │
-- │                          • RFDiffusion                             │
-- │                                ↓                                   │
-- │                         STRUCTURAL_AGENT                           │
-- └─────────────────────────────────────────────────────────────────────┘
--
-- Pipeline chaining (cross-NIM):
--
-- Drug Discovery Pipeline (STRUCTURAL_AGENT):
--   GenMol(CHEM) → validate(CHEM) → descriptors(CHEM) → DiffDock(STRUCT) → Boltz2(STRUCT)
--   Note: The pipeline procedure handles cross-domain calls internally.
--   The STRUCTURAL_AGENT owns the pipeline because the end-goal is structural scoring.
--
-- MSA-Structure Pipeline (STRUCTURAL_AGENT):
--   MSA-Search → OpenFold3
--   Both are structural tools. No cross-domain chaining.
--
-- Protein Binder Design (Workflow Template WF2, not a single procedure):
--   OpenFold2 → RFDiffusion → ProteinMPNN → Boltz-2
--   All in STRUCTURAL_AGENT. Orchestrated by execute_workflow_template.
--
-- Target-to-Structure (Workflow Template WF4):
--   DE(GENOMICS) → Pathway(GENOMICS) → PubMed(ORCH) → GeneValidate(GENOMICS)
--   → MSA(STRUCT) → OpenFold(STRUCT) → Boltz2(STRUCT)
--   Cross-domain: orchestrated by execute_workflow_template (ORCHESTRATOR).
--
-- =============================================================================

-- =============================================================================
-- NIM API Configuration (shared across all NIM-calling procedures)
-- =============================================================================
-- All NIM wrapper procedures share:
--   EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
--   SECRETS = ('nvidia_key' = SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
--
-- DUAL-MODE ENDPOINT ROUTING:
--   Procedures check NIM_ENDPOINTS config table for SPCS URLs first.
--   Falls back to hosted API if no SPCS entry. See nim_pipelines.sql for DDL.
--
-- Hosted API Endpoints (may differ from SPCS container paths):
--   GenMol:       https://health.api.nvidia.com/v1/biology/nvidia/genmol/generate
--   DiffDock:     https://health.api.nvidia.com/v1/biology/mit/diffdock
--   Boltz-2:      https://health.api.nvidia.com/v1/biology/nvidia/boltz-1
--   ProteinMPNN:  https://health.api.nvidia.com/v1/biology/nvidia/proteinmpnn
--   RFDiffusion:  https://health.api.nvidia.com/v1/biology/nvidia/rfdiffusion
--   MolMIM:       https://health.api.nvidia.com/v1/biology/nvidia/molmim
--   OpenFold2:    https://health.api.nvidia.com/v1/biology/nvidia/openfold2
--   OpenFold3:    https://health.api.nvidia.com/v1/biology/nvidia/openfold3
--   MSA-Search:   https://health.api.nvidia.com/v1/biology/nvidia/msa-search
--   Evo2:         https://health.api.nvidia.com/v1/biology/nvidia/evo2
--
-- SPCS Container Endpoints (VERIFIED from container /openapi.json):
--   Boltz-2:      /biology/mit/boltz2/predict   (VERIFIED 2026-08-26)
--   All others:   UNKNOWN — read from /openapi.json after each deployment
--   CRITICAL: Do NOT hardcode SPCS paths from documentation.
--
-- Deployment (GPU assignments, verified 2026-08-26):
--   P0: API mode (all calls to build.nvidia.com hosted endpoints)
--   P1: SPCS deployment:
--       - GenMol on A10G (GPU_NV_S, 24 GiB) — verified ran previously
--       - ProteinMPNN on A10G (GPU_NV_S) — license pre-accepted
--       - MolMIM on A10G (GPU_NV_S) — likely fits
--       - Boltz-2 on L40S (GPU_L40S_G1_16, 48 GiB) — VERIFIED working
--       - DiffDock on L40S (conservative)
--       - RFdiffusion on L40S (image mirrored, NOT served)
--       - OpenFold3 on L40S (RTX PRO 6000 compat unknown)
--       - MSA-Search on A10G + BLOCK VOLUME (ref DBs up to 1.2 TB)
--       - Evo2: BLOCKED (storage margin unmeasured, likely needs H100/H200)
--
-- GPU CAPACITY LADDER:
--   Capacity is per-instance-type, not per-GPU-family.
--   Walk instance types within a family before concluding unavailable.
--   Use DESCRIBE COMPUTE POOL (not SHOW) to read error_code.
--   CAPACITY_ERROR takes 12-19 min to surface.
--
-- /dev/shm: All NIM service specs need source:memory volume at /dev/shm (16 GiB).
-- NODE STORAGE: 93.13 GiB cap on ALL instance families (even H100/H200).
-- COST TRAP: A running service blocks pool auto-suspend.
-- GENMOL SPECIAL: Needs huggingface.co egress for tokenizer at model-init.
-- =============================================================================

-- =============================================================================
-- BioNeMo-Specific Agent Instructions
-- =============================================================================
-- These are already embedded in the domain agent specifications, but documented
-- here for reference:
--
-- CHEMISTRY_AGENT (GenMol):
--   - GenMol accepts SAFE notation internally (procedure handles conversion)
--   - Temperature parameter: string type ("0.7"), not float
--   - Always request more molecules than needed (~50% fail plausibility)
--   - Scoring modes: "QED" or "LogP"
--
-- STRUCTURAL_AGENT (DiffDock):
--   - Input: ligand SMILES + protein PDB content (ATOM records only)
--   - DiffDock field: ligand_file_type = "txt" for SMILES input
--   - Output: position_confidence (float array, rank 1 = best)
--   - Output: ligand_positions (SDF strings of docked poses)
--
-- STRUCTURAL_AGENT (Boltz-2):
--   - Input: polymers + ligands JSON structure
--   - polymers: [{id, molecule_type, sequence}]
--   - ligands: [{id, smiles, predict_affinity: true}]
--   - Output: mmCIF structure + pLDDT + pTM + pIC50 (if affinity requested)
--
-- STRUCTURAL_AGENT (ProteinMPNN):
--   - Input: PDB backbone content + num_samples + temperature
--   - model_name: "soluble" (default, optimized for soluble proteins)
--   - Output: designed sequences + scores
--
-- STRUCTURAL_AGENT (RFDiffusion):
--   - Input: target PDB + hotspot_residues (chain+residue, e.g. "A12,A45")
--   - binder_length: 30-300 residues
--   - Output: backbone PDB coordinates
--
-- =============================================================================

-- Verification: confirm all NIM procedures exist
SELECT name, function_reference, tool_type
FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
WHERE tool_type = 'procedure'
  AND (function_reference LIKE '%RUN_GENMOL%'
    OR function_reference LIKE '%RUN_DIFFDOCK%'
    OR function_reference LIKE '%RUN_BOLTZ2%'
    OR function_reference LIKE '%RUN_PROTEINMPNN%'
    OR function_reference LIKE '%RUN_RFDIFFUSION%'
    OR function_reference LIKE '%RUN_MOLMIM%'
    OR function_reference LIKE '%RUN_OPENFOLD%'
    OR function_reference LIKE '%RUN_MSA%'
    OR function_reference LIKE '%RUN_EVO2%'
    OR function_reference LIKE '%PIPELINE%')
ORDER BY name;
