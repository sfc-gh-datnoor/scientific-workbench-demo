-- =============================================================================
-- 14-tools.sql
-- Deploy all agent-callable tool procedures and seed the asset catalog.
-- Run as SYSADMIN with warehouse WORKBENCH_S
--
-- This is a manifest/runner script. Each tool lives in its own file under
-- tools/. Run them in the order listed below, then execute the SEED_ASSETS
-- call at the end. deploy.sh executes this phase automatically; this file
-- documents the exact sequence for manual deployment.
--
-- Prerequisites:
--   - setup/00 through 13 completed (databases, schemas, EAIs, secrets,
--     tool registry table, warehouses, RBAC)
--   - Reference data loaded (Phase 2) for tools that query reference tables
-- =============================================================================

USE ROLE SYSADMIN;
USE DATABASE SCIENTIFIC_WORKBENCH;
USE WAREHOUSE WORKBENCH_S;

-- =============================================================================
-- 1. NATIVE SNOWPARK TOOLS (7 procedures)
-- =============================================================================
-- Execute each file in order. These are Snowpark Python stored procedures
-- that run on a warehouse (no GPU needed).
--
-- File: tools/native/validate_gene_symbol.sql
--   Creates: CATALOG.VALIDATE_GENE_SYMBOL (function)
--   Purpose: HGNC gene symbol validation
--
-- File: tools/native/validate_molecule.sql
--   Creates: CATALOG.VALIDATE_MOLECULE (procedure)
--   Purpose: RDKit + PAINS filter on generated molecules
--
-- File: tools/native/calculate_molecular_descriptors.sql
--   Creates: CATALOG.CALCULATE_MOLECULAR_DESCRIPTORS (procedure)
--   Purpose: RDKit molecular property calculation from SMILES
--
-- File: tools/native/run_differential_expression.sql
--   Creates: CATALOG.RUN_DIFFERENTIAL_EXPRESSION (procedure)
--   Purpose: Mann-Whitney U test DE analysis with BH-FDR correction
--
-- File: tools/native/run_pathway_enrichment.sql
--   Creates: CATALOG.RUN_PATHWAY_ENRICHMENT (procedure)
--   Purpose: Over-representation analysis against MSigDB Hallmark gene sets
--
-- File: tools/native/run_survival_analysis.sql
--   Creates: CATALOG.RUN_SURVIVAL_ANALYSIS (procedure)
--   Purpose: Kaplan-Meier + log-rank + Cox PH survival analysis
--
-- File: tools/native/fetch_pdb.sql
--   Creates: CATALOG.FETCH_PDB (procedure)
--   Purpose: Fetch protein structure from RCSB PDB (requires PDB_API_EAI)

-- =============================================================================
-- 2. NVIDIA NIM WRAPPER TOOLS (8 procedures + 1 UDF + 2 pipelines)
-- =============================================================================
-- These wrap NVIDIA hosted API calls (and optionally SPCS endpoints).
-- All require NVIDIA_API_EAI external access integration from setup/00.
--
-- File: tools/nvidia/nim_boltz2.sql
--   Creates: CATALOG.RUN_BOLTZ2 (procedure)
--   Purpose: Protein structure + ligand affinity via Boltz-2
--
-- File: tools/nvidia/nim_genmol.sql
--   Creates: CATALOG.RUN_GENMOL (procedure)
--   Purpose: De novo molecule generation via GenMol
--
-- File: tools/nvidia/nim_diffdock.sql
--   Creates: CATALOG.RUN_DIFFDOCK (procedure)
--   Purpose: Molecular docking via DiffDock
--
-- File: tools/nvidia/nim_proteinmpnn.sql
--   Creates: CATALOG.RUN_PROTEINMPNN (procedure)
--   Purpose: Inverse folding (backbone to sequence) via ProteinMPNN
--
-- File: tools/nvidia/nim_rfdiffusion.sql
--   Creates: CATALOG.RUN_RFDIFFUSION (procedure)
--   Purpose: De novo protein backbone generation via RFdiffusion
--
-- File: tools/nvidia/nim_remaining.sql
--   Creates: CATALOG.RUN_MOLMIM, RUN_OPENFOLD2, RUN_OPENFOLD3,
--            RUN_MSA_SEARCH, RUN_EVO2 (5 procedures)
--   Purpose: MolMIM, OpenFold2, OpenFold3, MSA-Search, Evo2
--
-- File: tools/nvidia/nim_pipelines.sql
--   Creates: CATALOG.RUN_DRUG_DISCOVERY_PIPELINE,
--            CATALOG.RUN_MSA_STRUCTURE_PIPELINE (2 procedures)
--   Purpose: Multi-NIM chained workflows
--
-- File: tools/nvidia/nim_image_size.sql
--   Creates: CATALOG.NIM_IMAGE_SIZE (UDF)
--   Purpose: Probe OCI manifest from nvcr.io for image metadata
--
-- SKIP: tools/nvidia/mirror_nim_images.sql
--   (Image mirroring helper — run separately with --mirror-nims flag)

-- =============================================================================
-- 3. SEARCH TOOLS (2 procedures)
-- =============================================================================
-- File: tools/search/search_pubmed.sql
--   Creates: CATALOG.SEARCH_PUBMED (procedure)
--   Purpose: PubMed literature search via CKE (requires Marketplace subscription)
--
-- File: tools/search/search_tools.sql
--   Creates: CATALOG.SEARCH_CLINICAL_TRIALS, CATALOG.SEARCH_ASSET_CATALOG
--            (2 procedures)
--   Purpose: ClinicalTrials.gov CKE search + local asset catalog search

-- =============================================================================
-- 4. SEED ASSET CATALOG
-- =============================================================================
-- After all tools are deployed, populate the asset catalog with tool entries
-- and reference dataset entries (if Phase 2 data loading is complete).

CALL SCIENTIFIC_WORKBENCH.CATALOG.SEED_ASSETS();

-- =============================================================================
-- 5. VERIFICATION
-- =============================================================================
-- Confirm tool count in the registry.

SELECT 'Tool Registry' AS check_name,
       COUNT(*)        AS tool_count,
       CASE WHEN COUNT(*) >= 17 THEN 'PASS' ELSE 'FAIL — expected >= 17' END AS status
FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
WHERE status = 'active';
