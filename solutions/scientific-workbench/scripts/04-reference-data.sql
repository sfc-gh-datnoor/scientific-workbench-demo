-- =============================================================================
-- 04-reference-data.sql
-- Orchestrates loading of all reference datasets
-- Run as SYSADMIN using WORKBENCH_ML warehouse
-- =============================================================================
-- This script calls individual loaders from data/loaders/
-- Each loader is idempotent (safe to re-run)

USE WAREHOUSE WORKBENCH_ML;

-- HGNC gene nomenclature (small, load first — other tools depend on it)
-- Source: genenames.org/download/archive
-- See: data/loaders/load_hgnc.sql

-- Gene Ontology + annotations
-- Source: geneontology.org/docs/download-go-annotations
-- See: data/loaders/load_gene_ontology.sql

-- Reactome pathways
-- Source: reactome.org/download-data
-- See: data/loaders/load_reactome.sql

-- MSigDB gene sets (Hallmarks + Canonical Pathways)
-- Source: gsea-msigdb.org/gsea/msigdb
-- See: data/loaders/load_msigdb.sql

-- UniProt Swiss-Prot
-- Source: uniprot.org/downloads
-- See: data/loaders/load_uniprot.sql

-- ChEMBL (largest — load last)
-- Source: chembl.gitbook.io/chembl-interface-documentation/downloads
-- See: data/loaders/load_chembl.sql

-- ClinicalTrials.gov (structured data)
-- Source: clinicaltrials.gov/data-api
-- See: data/loaders/load_clinicaltrials.sql

-- =============================================================================
-- NOTE: Execute each loader script individually. They are designed to be run
-- in any order, but HGNC should be first (gene symbol validation depends on it).
--
-- The actual download + staging + COPY INTO logic is in each loader file.
-- This file serves as the orchestration reference and verification.
-- =============================================================================

-- Verification queries (run after all loaders complete)
SELECT 'HGNC' AS dataset, COUNT(*) AS row_count FROM WORKBENCH_REFERENCE.GENOMICS.HGNC_GENES
UNION ALL SELECT 'GO_TERMS', COUNT(*) FROM WORKBENCH_REFERENCE.PATHWAYS.GO_TERMS
UNION ALL SELECT 'REACTOME', COUNT(*) FROM WORKBENCH_REFERENCE.PATHWAYS.PATHWAYS
UNION ALL SELECT 'MSIGDB', COUNT(*) FROM WORKBENCH_REFERENCE.PATHWAYS.GENE_SETS
UNION ALL SELECT 'UNIPROT', COUNT(*) FROM WORKBENCH_REFERENCE.PROTEIN.UNIPROT_ENTRIES
UNION ALL SELECT 'CHEMBL_MOLECULES', COUNT(*) FROM WORKBENCH_REFERENCE.CHEMBL.MOLECULE_DICTIONARY
UNION ALL SELECT 'TRIALS', COUNT(*) FROM WORKBENCH_REFERENCE.CLINICAL.STUDIES;
