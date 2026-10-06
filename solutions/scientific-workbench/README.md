# Snowflake Scientific Workbench

> **Disclaimer:** This application is not part of the Snowflake Service and is governed by the terms in LICENSE, unless expressly agreed to in writing. You use this application at your own risk, and Snowflake has no obligation to support your use of this application. [Learn more](../../LEGAL.md)

An enterprise AI platform for life sciences R&D — built entirely on Snowflake.

## Requirements

- Snowflake account (Enterprise edition or higher recommended)
- Non-trial account (AI features — Cortex Agents, Cortex Search, Cortex LLM functions — must be enabled)
- ACCOUNTADMIN role (for initial setup; can be reduced to SYSADMIN after)
- Snowflake CLI (`snow`) installed and authenticated
- Node.js 20+ and npm (for app build/deployment)
- NVIDIA API key from [build.nvidia.com](https://build.nvidia.com) (free tier available)
- NGC API key from [ngc.nvidia.com](https://ngc.nvidia.com/setup/personal-keys) (optional, for SPCS NIM containers)

## Overview

A self-contained solution turning any Snowflake account into an AI-powered scientific discovery platform. Scientists and research teams get:

- **Discovery Agent**: Conversational scientific assistant orchestrated by **Claude Sonnet 5.5**, grounded in governed enterprise data and integrated with analytical semantic views.
- **23 Registered Scientific Tools**:
  - **10 NVIDIA BioNeMo NIMs**: GenMol (molecule generation), MolMIM (latent optimization), DiffDock (molecular docking), Boltz-2 (co-folding + binding affinity), ProteinMPNN (inverse folding), RFdiffusion (backbone design), OpenFold2/3 (structure prediction), Evo2 (genomic sequence generation), MSA-Search (ColabFold homology).
  - **8 Native Snowpark Tools**: Differential expression analysis, pathway enrichment, survival analysis, molecular descriptor calculation, gene symbol validation, molecule validation, and PDB retrieval.
  - **3 Search & Literature Tools**: PubMed CKE search, ClinicalTrials.gov search, and platform asset search.
  - **2 Meta-Pipelines**: End-to-end autonomous Drug Discovery Pipeline and MSA-Assisted Structure Pipeline.
- **4 Workflow Templates**: Deterministic protocols with intelligent agent execution (Hit Generation & Scoring, Protein Binder Design, Drug Discovery Pipeline, Target-to-Structure).
- **6 Life Sciences Notebooks**: Pre-packaged Snowflake Notebooks spanning oncology drug discovery, KRAS G12C targeting, single-cell RNA-seq, and binder engineering.
- **Modern Snowflake App Runtime (SAR) Application**: Next.js web application with 10 interactive modules (Chat, Explore, Asset Catalog, Experiments, Tools, Workflows, Notebooks, Share, Portfolio, Governance).

---

## Architecture

```
Snowflake App Runtime (Next.js Application Service)
    │
    ├── Cortex Discovery Agent (Claude Sonnet 5.5)
    │   ├── Multi-Agent Router & Toolsets
    │   ├── 4 Semantic Views (Genomics, Compounds, Clinical, Chemistry)
    │   └── Cortex Search (Tool Registry, Asset Search, PubMed)
    │
    ├── Scientific Tool Layer (23 Registered Tools)
    │   ├── NVIDIA BioNeMo NIM Wrappers (GPU Inference)
    │   ├── Native Snowpark Procedures & Functions
    │   └── Meta-Pipeline Orchestrators
    │
    ├── Data & Reference Layer
    │   ├── SCIENTIFIC_WORKBENCH (Catalog, Workflows, Results, Governance)
    │   ├── WORKBENCH_REFERENCE (ChEMBL, HGNC, UniProt, Target Data)
    │   └── WORKBENCH_PROJECTS (User Project Workspaces)
    │
    └── Governance & Provenance Layer
        ├── Immutable Provenance & Activity Logs
        ├── 20 Biological Plausibility Canaries
        └── RBAC (WORKBENCH_ADMIN / WORKBENCH_SCIENTIST / WORKBENCH_VIEWER)
```

---

## Quick Installation

```bash
# 1. Navigate to solution directory
cd solutions/scientific-workbench/

# 2. Run automated deployment
bash deploy.sh --connection <your-snowflake-connection>

# 3. Configure your NVIDIA API Key
# In Snowsight or SQL:
ALTER SECRET SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET SET SECRET_STRING = '<your-nvidia-key>';
```

See [NEXT_ACTIONS.md](./NEXT_ACTIONS.md) for post-install verification, sample queries, and persona exploration guides.
