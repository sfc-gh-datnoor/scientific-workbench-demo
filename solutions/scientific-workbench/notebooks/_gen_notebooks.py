"""Generate protein_binder_design.ipynb and single_cell_rnaseq.ipynb"""

import json
import pathlib


def _src(code_str):
    """Split a (possibly multiline) string into nbformat source list."""
    lines = code_str.splitlines(keepends=True)
    # ensure last line has no trailing newline in source list
    if lines and lines[-1].endswith("\n"):
        lines[-1] = lines[-1].rstrip("\n")
    return lines


def cell_md(src, cid):
    return {"cell_type": "markdown", "id": cid, "metadata": {}, "source": _src(src)}


def cell_code(src, cid):
    return {"cell_type": "code", "id": cid, "metadata": {}, "execution_count": None, "outputs": [], "source": _src(src)}


def notebook(cells):
    return {
        "nbformat": 4,
        "nbformat_minor": 5,
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python", "version": "3.9.0"},
        },
        "cells": cells,
    }


# =============================================================================
# Notebook 1: Protein Binder Design
# =============================================================================

nb1 = notebook(
    [
        cell_md(
            "# Protein Binder Design: EGFR Kinase Domain\n"
            "\n"
            "**Objective:** Design a high-affinity protein binder for the EGFR kinase domain\n"
            "using a structure-guided AI pipeline.\n"
            "\n"
            "**Workflow:**\n"
            "1. Target Selection — Fetch EGFR structure (PDB: 6OIM) and analyse binding interface\n"
            "2. Backbone Design — RFdiffusion generates binder scaffolds around hotspot residues\n"
            "3. Sequence Design — ProteinMPNN threads sequences onto backbones\n"
            "4. Complex Validation — Boltz-2 predicts binding mode and affinity\n"
            "\n"
            "**Platform:** Snowflake Scientific Workbench | Notebooks-in-Workspaces  \n"
            "**NVIDIA NIMs:** RFdiffusion · ProteinMPNN · Boltz-2 (require API key)  \n"
            "**Governance:** All steps logged to PROVENANCE_LOG automatically",
            "a001",
        ),
        cell_code(
            "from workbench_helpers import Workbench\n"
            "import pandas as pd\n"
            "import numpy as np\n"
            "import matplotlib.pyplot as plt\n"
            "\n"
            "wb      = Workbench(database='SCIENTIFIC_WORKBENCH', warehouse='WORKBENCH_S')\n"
            "session = wb.session\n"
            "print(f'Connected as : {session.sql(\"SELECT CURRENT_USER()\").collect()[0][0]}')\n"
            "print(f'Warehouse    : {wb.warehouse}')",
            "a002",
        ),
        cell_code(
            "TARGET_PDB_ID    = '6OIM'              # EGFR kinase domain (erlotinib-bound)\n"
            "HOTSPOT_RESIDUES = 'A696,A719,A855'    # ATP-binding pocket residues\n"
            "BINDER_LENGTH    = 60\n"
            "N_DESIGNS        = 10\n"
            "N_SEQUENCES      = 8\n"
            "\n"
            "RESULTS_SCHEMA = 'WORKBENCH_PROJECTS.SHARED_ANALYTICS'\n"
            "CATALOG        = 'SCIENTIFIC_WORKBENCH.CATALOG'\n"
            "\n"
            "print('Configuration loaded.')\n"
            "print(f'  Target PDB        : {TARGET_PDB_ID}')\n"
            "print(f'  Hotspot residues  : {HOTSPOT_RESIDUES}')\n"
            "print(f'  Binder length     : {BINDER_LENGTH} residues')\n"
            "print(f'  Designs requested : {N_DESIGNS}')",
            "a003",
        ),
        cell_md(
            "---\n"
            "## Phase 1 — Target Selection & Structure Analysis\n"
            "\n"
            "Fetch the EGFR crystal structure from RCSB (public REST API) and characterise\n"
            "the binding interface. **No NVIDIA API key required for this phase.**",
            "a004",
        ),
        cell_code(
            "# Query the tool registry for structural/protein-design tools\n"
            "tools_df = session.sql(\n"
            "    'SELECT tool_id, display_name, domain, status '\n"
            "    'FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS '\n"
            "    \"WHERE status = \\'active\\' ORDER BY display_name\"\n"
            ").to_pandas()\n"
            "print(f'Registered tools ({len(tools_df)} total):')\n"
            "print(tools_df[['tool_id','display_name','status']].to_string(index=False))",
            "a005",
        ),
        cell_code(
            "# FETCH_PDB calls RCSB (public REST, no API key needed)\n"
            "PDB_TABLE = f'{RESULTS_SCHEMA}.EGFR_STRUCTURE_RAW'\n"
            "pdb_text  = None\n"
            "fetch_ok  = False\n"
            "\n"
            "try:\n"
            "    session.sql(f'CALL {CATALOG}.FETCH_PDB(\\'{TARGET_PDB_ID}\\', \\'{PDB_TABLE}\\')').collect()\n"
            "    row = session.sql(f'SELECT pdb_content FROM {PDB_TABLE} LIMIT 1').collect()\n"
            "    if row:\n"
            "        pdb_text = row[0][0]\n"
            "        fetch_ok = True\n"
            "        print(f'FETCH_PDB succeeded  — {len(pdb_text):,} characters')\n"
            "    else:\n"
            "        raise RuntimeError('Empty result from FETCH_PDB')\n"
            "except Exception as e:\n"
            "    print(f'FETCH_PDB procedure failed ({e}); trying direct RCSB download...')\n"
            "    try:\n"
            "        import urllib.request\n"
            "        url = f'https://files.rcsb.org/download/{TARGET_PDB_ID}.pdb'\n"
            "        with urllib.request.urlopen(url, timeout=15) as r:\n"
            "            pdb_text = r.read().decode()\n"
            "        fetch_ok = True\n"
            "        print(f'Direct RCSB download succeeded — {len(pdb_text):,} characters')\n"
            "    except Exception as e2:\n"
            "        print(f'Direct download also failed: {e2}')\n"
            "        print('Continuing with placeholder structure metadata.')",
            "a006",
        ),
        cell_code(
            "def parse_pdb(text):\n"
            "    chains = {}\n"
            "    for line in text.splitlines():\n"
            "        if not line.startswith('ATOM'):\n"
            "            continue\n"
            "        chain = line[21]\n"
            "        try:\n"
            "            resseq = int(line[22:26].strip())\n"
            "        except ValueError:\n"
            "            continue\n"
            "        chains.setdefault(chain, set()).add(resseq)\n"
            "    return {c: sorted(v) for c, v in sorted(chains.items())}\n"
            "\n"
            "if pdb_text:\n"
            "    chain_res = parse_pdb(pdb_text)\n"
            "    total_res = sum(len(v) for v in chain_res.values())\n"
            "    print(f'PDB {TARGET_PDB_ID} — chain summary')\n"
            '    print(f\'  {"Chain":<8} {"Residues":>10}  Range\')\n'
            '    print(f\'  {"-"*8} {"-"*10}  {"-"*18}\')\n'
            "    for ch, res in chain_res.items():\n"
            "        rng = f'{res[0]}-{res[-1]}' if res else '-'\n"
            "        print(f'  {ch:<8} {len(res):>10}  {rng}')\n"
            "    print(f'  {\"TOTAL\":<8} {total_res:>10}')\n"
            "    hetatm = [l for l in pdb_text.splitlines()\n"
            "              if l.startswith('HETATM') and l[17:20].strip() not in ('HOH','WAT')]\n"
            "    ligands = {l[17:20].strip() for l in hetatm}\n"
            "    print(f'  Ligands: {ligands if ligands else \"none\"}')\n"
            "else:\n"
            "    chain_res = {'A': list(range(696, 1022))}\n"
            "    total_res = 326\n"
            "    print(f'Placeholder: 1 chain (A), ~{total_res} residues')\n"
            "\n"
            "# Bar chart\n"
            "fig, ax = plt.subplots(figsize=(5, 3))\n"
            "ax.bar(chain_res.keys(), [len(v) for v in chain_res.values()],\n"
            "       color='#6366f1', edgecolor='white')\n"
            "ax.set_xlabel('Chain'); ax.set_ylabel('Residues')\n"
            "ax.set_title(f'PDB {TARGET_PDB_ID} — Residues per Chain')\n"
            "plt.tight_layout(); plt.show()",
            "a007",
        ),
        cell_md(
            "---\n"
            "## Phase 2 — Binder Backbone Design (RFdiffusion)\n"
            "\n"
            "RFdiffusion generates diverse protein backbone geometries complementary to the\n"
            "EGFR hotspot surface. **Requires NVIDIA BioNeMo API key.**\n"
            "\n"
            "> **To enable:** `ALTER SECRET SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_KEY`  \n"
            "> `SET SECRET_STRING = '<your-ngc-api-key>';`  \n"
            "> Obtain a key at https://build.nvidia.com/",
            "a008",
        ),
        cell_code(
            "BACKBONE_TABLE = f'{RESULTS_SCHEMA}.BINDER_BACKBONES'\n"
            "rfdiffusion_ok = False\n"
            "backbones_df   = None\n"
            "\n"
            "try:\n"
            "    session.sql(\n"
            "        f'CALL {CATALOG}.RUN_RFDIFFUSION('\n"
            "        f\"  \\'@{CATALOG}.STRUCTURES/{TARGET_PDB_ID}.pdb\\',\"\n"
            "        f\"  \\'{HOTSPOT_RESIDUES}\\',\"\n"
            "        f'  {BINDER_LENGTH},'\n"
            "        f'  {N_DESIGNS},'\n"
            "        f\"  \\'{BACKBONE_TABLE}\\'\"\n"
            "        f')'\n"
            "    ).collect()\n"
            "    backbones_df   = session.table(BACKBONE_TABLE).to_pandas()\n"
            "    print(f'RFdiffusion: generated {len(backbones_df)} backbones')\n"
            "    rfdiffusion_ok = True\n"
            "\n"
            "except Exception as e:\n"
            "    err = str(e)\n"
            "    print('=' * 62)\n"
            "    if '401' in err or 'nauthorized' in err:\n"
            "        print('RFdiffusion SKIPPED — NVIDIA API key not configured.')\n"
            "        print()\n"
            "        print('  ALTER SECRET SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_KEY')\n"
            "        print('    SET SECRET_STRING = \\'<your-ngc-api-key>\\';')\n"
            "    else:\n"
            "        print(f'RFdiffusion SKIPPED — {err}')\n"
            "    print('=' * 62)\n"
            "    rng_b = np.random.default_rng(42)\n"
            "    backbones_df = pd.DataFrame({\n"
            "        'DESIGN_ID':     [f'backbone_{i:02d}' for i in range(N_DESIGNS)],\n"
            "        'PDB_STAGE_PATH':[f'@{CATALOG}.RESULTS/bb_{i:02d}.pdb' for i in range(N_DESIGNS)],\n"
            "        'PLDDT_MEAN':    np.round(rng_b.uniform(0.70, 0.92, N_DESIGNS), 3),\n"
            "        'IPAE':          np.round(rng_b.uniform(0.05, 0.30, N_DESIGNS), 3),\n"
            "        'STATUS':        ['PLACEHOLDER'] * N_DESIGNS,\n"
            "    })\n"
            "    print(f'Using {N_DESIGNS}-row placeholder backbone table.')",
            "a009",
        ),
        cell_md(
            "---\n"
            "## Phase 3 — Sequence Design (ProteinMPNN)\n"
            "\n"
            "ProteinMPNN designs amino-acid sequences that fold into the generated backbones\n"
            "while optimising for stability and target complementarity.\n"
            "**Requires NVIDIA BioNeMo API key.**",
            "a010",
        ),
        cell_code(
            "SEQUENCE_TABLE = f'{RESULTS_SCHEMA}.BINDER_SEQUENCES'\n"
            "proteinmpnn_ok = False\n"
            "sequences_df   = None\n"
            "\n"
            "best_bb   = backbones_df.sort_values('IPAE').iloc[0]\n"
            "bb_path   = best_bb['PDB_STAGE_PATH']\n"
            "\n"
            "try:\n"
            "    session.sql(\n"
            "        f'CALL {CATALOG}.RUN_PROTEINMPNN('\n"
            "        f\"  \\'{bb_path}\\',\"\n"
            "        f'  {N_SEQUENCES},'\n"
            "        f'  0.1,'\n"
            "        f\"  \\'{SEQUENCE_TABLE}\\'\"\n"
            "        f')'\n"
            "    ).collect()\n"
            "    sequences_df   = session.table(SEQUENCE_TABLE).to_pandas()\n"
            "    print(f'ProteinMPNN: {len(sequences_df)} sequences designed')\n"
            "    proteinmpnn_ok = True\n"
            "\n"
            "except Exception as e:\n"
            "    err = str(e)\n"
            "    print('=' * 62)\n"
            "    if '401' in err or 'nauthorized' in err:\n"
            "        print('ProteinMPNN SKIPPED — NVIDIA API key not configured.')\n"
            "        print()\n"
            "        print('  ALTER SECRET SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_KEY')\n"
            "        print('    SET SECRET_STRING = \\'<your-ngc-api-key>\\';')\n"
            "    else:\n"
            "        print(f'ProteinMPNN SKIPPED — {err}')\n"
            "    print('=' * 62)\n"
            "    rng_s = np.random.default_rng(42)\n"
            "    aa    = list('ACDEFGHIKLMNPQRSTVWY')\n"
            "    sequences_df = pd.DataFrame({\n"
            "        'SEQUENCE_ID': [f'seq_{i:03d}' for i in range(N_SEQUENCES)],\n"
            "        'SEQUENCE':    [''.join(rng_s.choice(aa, BINDER_LENGTH)) for _ in range(N_SEQUENCES)],\n"
            "        'SCORE':       np.round(rng_s.uniform(-1.5, -0.8, N_SEQUENCES), 3),\n"
            "        'STATUS':      ['PLACEHOLDER'] * N_SEQUENCES,\n"
            "    })\n"
            "    print(f'Using {N_SEQUENCES}-row placeholder sequence table.')",
            "a011",
        ),
        cell_md(
            "---\n"
            "## Phase 4 — Complex Validation (Boltz-2)\n"
            "\n"
            "Boltz-2 co-folds the designed binder with the EGFR target to predict binding\n"
            "geometry and estimated affinity (ipTM score). **Requires NVIDIA BioNeMo API key.**",
            "a012",
        ),
        cell_code(
            "BOLTZ_TABLE = f'{RESULTS_SCHEMA}.BINDER_VALIDATION'\n"
            "boltz_ok    = False\n"
            "val_df      = None\n"
            "\n"
            "top_seq   = sequences_df.sort_values('SCORE').iloc[0]['SEQUENCE']\n"
            "# Abbreviated EGFR stub + ':' + binder (Boltz-2 chain separator)\n"
            "egfr_stub = 'KVLGSGAFGTVYKGLWIPEGEKVKIPVAIKELREATSPKANKEILDEAYVMASVDNPHVCRLLGICLTSTVQLITQLMP'\n"
            "binder_input = f'{egfr_stub}:{top_seq}'\n"
            "\n"
            "try:\n"
            "    session.sql(\n"
            "        f'CALL {CATALOG}.RUN_BOLTZ2('\n"
            "        f\"  \\'{binder_input}\\',\"\n"
            "        f\"  \\'N/A\\',\"\n"
            "        f\"  \\'protein_protein\\',\"\n"
            "        f\"  \\'{BOLTZ_TABLE}\\'\"\n"
            "        f')'\n"
            "    ).collect()\n"
            "    val_df   = session.table(BOLTZ_TABLE).to_pandas()\n"
            "    print(f'Boltz-2: {len(val_df)} complex structures predicted')\n"
            "    boltz_ok = True\n"
            "\n"
            "except Exception as e:\n"
            "    err = str(e)\n"
            "    print('=' * 62)\n"
            "    if '401' in err or 'nauthorized' in err:\n"
            "        print('Boltz-2 SKIPPED — NVIDIA API key not configured.')\n"
            "        print()\n"
            "        print('  ALTER SECRET SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_KEY')\n"
            "        print('    SET SECRET_STRING = \\'<your-ngc-api-key>\\';')\n"
            "    else:\n"
            "        print(f'Boltz-2 SKIPPED — {err}')\n"
            "    print('=' * 62)\n"
            "    rng_v = np.random.default_rng(42)\n"
            "    val_df = pd.DataFrame({\n"
            "        'COMPLEX_ID':        [f'complex_{i:02d}' for i in range(5)],\n"
            "        'IPTM':              np.round(rng_v.uniform(0.4, 0.82, 5), 3),\n"
            "        'PLDDT_BINDER':      np.round(rng_v.uniform(0.65, 0.91, 5), 3),\n"
            "        'STATUS':            ['PLACEHOLDER'] * 5,\n"
            "    })\n"
            "    print(f'Using 5-row placeholder validation table.')",
            "a013",
        ),
        cell_md("---\n## Phase 5 — Results Summary & Provenance", "a014"),
        cell_code(
            "fig, axes = plt.subplots(1, 3, figsize=(14, 4))\n"
            "fig.suptitle('Protein Binder Design Pipeline — Results', fontsize=13, fontweight='bold')\n"
            "\n"
            "axes[0].hist(backbones_df['PLDDT_MEAN'], bins=8, color='#6366f1', edgecolor='white', alpha=0.85)\n"
            "axes[0].axvline(backbones_df['PLDDT_MEAN'].mean(), color='crimson', ls='--', lw=1.5,\n"
            "                label=f'mean={backbones_df[\"PLDDT_MEAN\"].mean():.2f}')\n"
            "axes[0].set_title('RFdiffusion — Backbone pLDDT'); axes[0].legend()\n"
            "axes[0].set_xlabel('pLDDT'); axes[0].set_ylabel('Count')\n"
            "\n"
            "axes[1].hist(sequences_df['SCORE'], bins=6, color='#10b981', edgecolor='white', alpha=0.85)\n"
            "axes[1].set_title('ProteinMPNN — Sequence Score')\n"
            "axes[1].set_xlabel('Score (lower = better)'); axes[1].set_ylabel('Count')\n"
            "\n"
            "axes[2].barh(val_df['COMPLEX_ID'], val_df['IPTM'], color='#f59e0b', edgecolor='white')\n"
            "axes[2].axvline(0.6, color='crimson', ls='--', lw=1.5, label='ipTM > 0.6 threshold')\n"
            "axes[2].set_title('Boltz-2 — Predicted ipTM'); axes[2].legend()\n"
            "axes[2].set_xlabel('ipTM')\n"
            "\n"
            "plt.tight_layout(); plt.show()\n"
            "\n"
            "print('\\nPipeline step status:')\n"
            "for step, ok in [('FETCH_PDB (RCSB, no key)', fetch_ok),\n"
            "                  ('RFdiffusion backbone',     rfdiffusion_ok),\n"
            "                  ('ProteinMPNN sequence',     proteinmpnn_ok),\n"
            "                  ('Boltz-2 validation',       boltz_ok)]:\n"
            "    status = 'OK' if ok else 'SKIPPED (key needed)'\n"
            "    print(f'  {step:<30s}  {status}')",
            "a015",
        ),
        cell_code(
            "wb.log_decision(\n"
            "    f'Protein binder design for EGFR kinase domain (PDB {TARGET_PDB_ID}). '\n"
            "    f'Hotspots: {HOTSPOT_RESIDUES}. '\n"
            "    f'Generated {N_DESIGNS} backbone designs, {N_SEQUENCES} sequences per backbone. '\n"
            "    'NVIDIA NIM steps (RFdiffusion, ProteinMPNN, Boltz-2) require API key.',\n"
            "    evidence=f'PDB {TARGET_PDB_ID} parsed ({total_res} residues); BioNeMo NIMs'\n"
            ")\n"
            "print('Provenance logged.')\n"
            "print('\\nNext steps:')\n"
            "print('  1. Set NVIDIA_API_KEY secret to enable live NIM calls')\n"
            "print('  2. Inspect backbone PDB files on the STRUCTURES stage')\n"
            "print('  3. Submit top Boltz-2 binders (ipTM > 0.6) for wet-lab synthesis')",
            "a016",
        ),
    ]
)  # end nb1


# =============================================================================
# Notebook 2: Single-Cell RNA-seq
# =============================================================================

nb2 = notebook(
    [
        cell_md(
            "# Single-Cell RNA-seq Analysis\n"
            "\n"
            "**Objective:** End-to-end scRNA-seq analysis on a synthetic 500-cell × 2000-gene\n"
            "count matrix — QC, normalisation, HVG selection, PCA, 2D embedding, KMeans\n"
            "clustering — with results written to a Snowflake table.\n"
            "\n"
            "**Note:** No real scRNA tables are required; all data are generated in-notebook.\n"
            "\n"
            "**Library dependencies (pre-installed in Workspaces):** numpy · pandas · sklearn · matplotlib  \n"
            "**Optional:** umap-learn *(PCA 2D fallback if absent — notebook always runs)*",
            "b001",
        ),
        cell_code(
            "# Uncomment to install optional UMAP library:\n"
            "# %pip install umap-learn\n"
            "\n"
            "import numpy as np\n"
            "import pandas as pd\n"
            "import matplotlib.pyplot as plt\n"
            "from sklearn.decomposition import PCA\n"
            "from sklearn.preprocessing import StandardScaler\n"
            "from sklearn.cluster import KMeans\n"
            "\n"
            "try:\n"
            "    import umap as umap_lib\n"
            "    UMAP_AVAILABLE = True\n"
            "    print('umap-learn available — will use UMAP embedding')\n"
            "except ImportError:\n"
            "    UMAP_AVAILABLE = False\n"
            "    print('umap-learn not installed — PCA 2D projection will be used (UMAP placeholder)')\n"
            "\n"
            "from workbench_helpers import Workbench\n"
            "wb      = Workbench(database='SCIENTIFIC_WORKBENCH', warehouse='WORKBENCH_S')\n"
            "session = wb.session\n"
            "print(f'Connected as: {session.sql(\"SELECT CURRENT_USER()\").collect()[0][0]}')",
            "b002",
        ),
        cell_code(
            "RANDOM_SEED   = 42\n"
            "N_CELLS       = 500\n"
            "N_GENES       = 2000\n"
            "N_CLUSTERS    = 5\n"
            "N_MT_GENES    = 50\n"
            "N_HVG         = 500\n"
            "N_PCA_COMPS   = 50\n"
            "N_PCA_EMBED   = 30\n"
            "\n"
            "RESULTS_TABLE = 'WORKBENCH_PROJECTS.SHARED_ANALYTICS.SCRNA_CELL_EMBEDDINGS'\n"
            "\n"
            "print(f'Experiment : {N_CELLS} cells x {N_GENES} genes, {N_CLUSTERS} clusters')\n"
            "print(f'Results    : {RESULTS_TABLE}')",
            "b003",
        ),
        cell_md(
            "---\n"
            "## Phase 1 — Synthetic Count Matrix Generation\n"
            "\n"
            "A Poisson-based generative model creates a count matrix with:\n"
            "- **5 biologically distinct clusters** (marker gene programmes per cluster)\n"
            "- **Mitochondrial genes** (first 50 features, labelled `MT-*`)\n"
            "- **Deterministic** — seeded with `RANDOM_SEED = 42`",
            "b004",
        ),
        cell_code(
            "rng = np.random.default_rng(RANDOM_SEED)\n"
            "\n"
            "gene_names = [f'MT-GENE_{i:02d}' for i in range(N_MT_GENES)] + \\\n"
            "             [f'GENE_{i:04d}' for i in range(N_MT_GENES, N_GENES)]\n"
            "cell_ids   = [f'CELL_{i:04d}' for i in range(N_CELLS)]\n"
            "\n"
            "# Balanced cluster assignment\n"
            "cell_clusters = np.tile(np.arange(N_CLUSTERS), N_CELLS // N_CLUSTERS)\n"
            "if N_CELLS % N_CLUSTERS:\n"
            "    cell_clusters = np.append(cell_clusters, np.arange(N_CELLS % N_CLUSTERS))\n"
            "rng.shuffle(cell_clusters)\n"
            "\n"
            "# Per-cluster mean expression programmes in log space\n"
            "cluster_means = rng.normal(0.0, 1.5, (N_CLUSTERS, N_GENES))\n"
            "for k in range(N_CLUSTERS):   # marker genes make clusters separable\n"
            "    cluster_means[k, k*100 : k*100 + 80] += 3.0\n"
            "\n"
            "# Poisson count matrix\n"
            "log_lambda = cluster_means[cell_clusters] + rng.normal(0, 0.4, (N_CELLS, N_GENES))\n"
            "rates      = np.exp(log_lambda) + 0.05\n"
            "counts     = rng.poisson(rates).astype(np.float32)\n"
            "\n"
            "print(f'Count matrix shape   : {counts.shape}')\n"
            "print(f'Total UMIs           : {counts.sum():,.0f}')\n"
            "print(f'Median UMIs / cell   : {np.median(counts.sum(axis=1)):.0f}')\n"
            "print(f'Sparsity             : {(counts == 0).mean():.1%} zeros')\n"
            "print(f'Cluster sizes        : {np.bincount(cell_clusters)}')",
            "b005",
        ),
        cell_md("---\n## Phase 2 — Quality Control", "b006"),
        cell_code(
            "lib_size = counts.sum(axis=1)\n"
            "n_genes  = (counts > 0).sum(axis=1)\n"
            "mt_frac  = counts[:, :N_MT_GENES].sum(axis=1) / (lib_size + 1e-9)\n"
            "\n"
            "lib_lo, lib_hi = np.percentile(lib_size, [2.5, 97.5])\n"
            "mt_hi          = 0.25\n"
            "qc_pass = (lib_size >= lib_lo) & (lib_size <= lib_hi) & (mt_frac <= mt_hi)\n"
            "print(f'QC: {qc_pass.sum()} / {N_CELLS} cells pass')\n"
            "\n"
            "fig, axes = plt.subplots(1, 3, figsize=(13, 4))\n"
            "fig.suptitle('QC Metrics', fontsize=12, fontweight='bold')\n"
            "for ax, data, lbl, thr in zip(\n"
            "    axes,\n"
            "    [lib_size, n_genes, mt_frac * 100],\n"
            "    ['Library size (UMIs)', 'Genes detected', 'MT fraction (%)'],\n"
            "    [None, None, mt_hi * 100],\n"
            "):\n"
            "    ax.hist(data, bins=40, color='#6366f1', edgecolor='white', alpha=0.8)\n"
            "    ax.set_xlabel(lbl); ax.set_ylabel('Cells')\n"
            "    if thr is not None:\n"
            "        ax.axvline(thr, color='crimson', ls='--', lw=1.5, label=f'threshold {thr:.1f}')\n"
            "        ax.legend()\n"
            "plt.tight_layout(); plt.show()\n"
            "\n"
            "counts_qc  = counts[qc_pass]\n"
            "cell_ids_qc = [cell_ids[i] for i in np.where(qc_pass)[0]]\n"
            "clusters_qc = cell_clusters[qc_pass]\n"
            "print(f'Post-QC matrix: {counts_qc.shape}')",
            "b007",
        ),
        cell_md("---\n## Phase 3 — Normalisation & Highly Variable Gene Selection", "b008"),
        cell_code(
            "# CP10K log-normalisation\n"
            "lib_qc  = counts_qc.sum(axis=1, keepdims=True)\n"
            "norm    = counts_qc / lib_qc * 1e4\n"
            "log1p   = np.log1p(norm)\n"
            "\n"
            "# HVG: select by dispersion (var / mean)\n"
            "mean_g = log1p.mean(axis=0)\n"
            "var_g  = log1p.var(axis=0)\n"
            "disp   = var_g / (mean_g + 1e-9)\n"
            "\n"
            "hvg_idx   = np.argsort(disp)[-N_HVG:]\n"
            "hvg_names = [gene_names[i] for i in hvg_idx]\n"
            "X_hvg     = log1p[:, hvg_idx]\n"
            "print(f'HVG matrix: {X_hvg.shape} (cells x HVGs)')\n"
            "\n"
            "fig, ax = plt.subplots(figsize=(6, 4))\n"
            "ax.scatter(mean_g, disp, s=3, alpha=0.3, c='#94a3b8', label='All genes')\n"
            "ax.scatter(mean_g[hvg_idx], disp[hvg_idx], s=6, alpha=0.6, c='#ef4444',\n"
            "           label=f'HVGs (n={N_HVG})')\n"
            "ax.set_xlabel('Mean expression (log1p)'); ax.set_ylabel('Dispersion')\n"
            "ax.set_title('HVG Selection'); ax.legend()\n"
            "plt.tight_layout(); plt.show()",
            "b009",
        ),
        cell_md("---\n## Phase 4 — PCA", "b010"),
        cell_code(
            "scaler  = StandardScaler()\n"
            "X_sc    = scaler.fit_transform(X_hvg)\n"
            "\n"
            "pca     = PCA(n_components=N_PCA_COMPS, random_state=RANDOM_SEED)\n"
            "X_pca   = pca.fit_transform(X_sc)\n"
            "var_exp = pca.explained_variance_ratio_\n"
            "\n"
            "print(f'PCA shape           : {X_pca.shape}')\n"
            "print(f'Cumulative var (50) : {var_exp.sum():.1%}')\n"
            "\n"
            "PALETTE = plt.cm.tab10(np.linspace(0, 0.5, N_CLUSTERS))\n"
            "fig, axes = plt.subplots(1, 2, figsize=(12, 4))\n"
            "\n"
            "axes[0].bar(range(1, 21), var_exp[:20]*100, color='#6366f1')\n"
            "axes[0].set_xlabel('PC'); axes[0].set_ylabel('% Variance Explained')\n"
            "axes[0].set_title('Scree Plot')\n"
            "\n"
            "for k in range(N_CLUSTERS):\n"
            "    m = clusters_qc == k\n"
            "    axes[1].scatter(X_pca[m,0], X_pca[m,1], s=8, alpha=0.6,\n"
            "                    color=PALETTE[k], label=f'Cluster {k}')\n"
            "axes[1].set_xlabel('PC1'); axes[1].set_ylabel('PC2')\n"
            "axes[1].set_title('PCA — PC1 vs PC2 (true labels)'); axes[1].legend(markerscale=2, fontsize=8)\n"
            "plt.tight_layout(); plt.show()",
            "b011",
        ),
        cell_md(
            "---\n"
            "## Phase 5 — 2D Embedding\n"
            "\n"
            "Uses UMAP if `umap-learn` is installed; otherwise falls back to PCA 2D\n"
            "(labelled *PCA (UMAP placeholder)*) so the notebook always runs end-to-end.",
            "b012",
        ),
        cell_code(
            "X_embed = X_pca[:, :N_PCA_EMBED]\n"
            "\n"
            "if UMAP_AVAILABLE:\n"
            "    reducer     = umap_lib.UMAP(n_components=2, n_neighbors=15, min_dist=0.1,\n"
            "                                random_state=RANDOM_SEED)\n"
            "    X_2d        = reducer.fit_transform(X_embed)\n"
            "    embed_label = 'UMAP'\n"
            "    print(f'UMAP embedding: {X_2d.shape}')\n"
            "else:\n"
            "    X_2d        = X_pca[:, :2]\n"
            "    embed_label = 'PCA (UMAP placeholder)'\n"
            "    print(f'PCA 2D fallback: {X_2d.shape}')\n"
            "\n"
            "print(f'Embedding method: {embed_label}')",
            "b013",
        ),
        cell_md("---\n## Phase 6 — Clustering (KMeans as Leiden Substitute)", "b014"),
        cell_code(
            "# KMeans on top-30 PCs (Leiden substitute — noted in output)\n"
            "km      = KMeans(n_clusters=N_CLUSTERS, random_state=RANDOM_SEED, n_init=10)\n"
            "km_lbls = km.fit_predict(X_embed)\n"
            "print(f'KMeans cluster sizes: {np.bincount(km_lbls)}')\n"
            "print('(Note: KMeans on PCA top PCs is used as a Leiden substitute.)')\n"
            "print('  Install leidenalg + igraph for graph-based clustering.')\n"
            "\n"
            "PALETTE = plt.cm.tab10(np.linspace(0, 0.5, N_CLUSTERS))\n"
            "fig, axes = plt.subplots(1, 2, figsize=(12, 5))\n"
            "ax0lbl = embed_label.split()[0]\n"
            "\n"
            "for ax, labels, title in zip(\n"
            "    axes,\n"
            "    [clusters_qc, km_lbls],\n"
            "    [f'{embed_label} — True Labels', f'{embed_label} — KMeans Labels'],\n"
            "):\n"
            "    for k in range(N_CLUSTERS):\n"
            "        m = labels == k\n"
            "        ax.scatter(X_2d[m,0], X_2d[m,1], s=8, alpha=0.65,\n"
            "                   color=PALETTE[k], label=f'Cluster {k}')\n"
            "    ax.set_xlabel(f'{ax0lbl} 1'); ax.set_ylabel(f'{ax0lbl} 2')\n"
            "    ax.set_title(title); ax.legend(markerscale=2, fontsize=8)\n"
            "\n"
            "plt.tight_layout(); plt.show()",
            "b015",
        ),
        cell_md("---\n## Phase 7 — Save Results to Snowflake", "b016"),
        cell_code(
            "results = pd.DataFrame({\n"
            "    'CELL_ID':          cell_ids_qc,\n"
            "    'TRUE_CLUSTER':     clusters_qc.astype(int),\n"
            "    'KMEANS_CLUSTER':   km_lbls.astype(int),\n"
            "    'PC1':              X_pca[:, 0].astype(float),\n"
            "    'PC2':              X_pca[:, 1].astype(float),\n"
            "    'EMBED_X':          X_2d[:, 0].astype(float),\n"
            "    'EMBED_Y':          X_2d[:, 1].astype(float),\n"
            "    'LIB_SIZE':         lib_qc.flatten().astype(int),\n"
            "    'N_GENES_DETECTED': (counts_qc > 0).sum(axis=1).astype(int),\n"
            "    'MT_FRACTION':      mt_frac[qc_pass].astype(float),\n"
            "    'EMBED_METHOD':     embed_label,\n"
            "})\n"
            "\n"
            "# Write to Snowflake via Snowpark\n"
            "snow_df = session.create_dataframe(results)\n"
            "snow_df.write.mode('overwrite').save_as_table(RESULTS_TABLE)\n"
            "print(f'Wrote {len(results)} rows to {RESULTS_TABLE}')\n"
            "\n"
            "# Verify\n"
            "n_written = session.sql(f'SELECT COUNT(*) FROM {RESULTS_TABLE}').collect()[0][0]\n"
            "print(f'SELECT COUNT(*) -> {n_written} rows')\n"
            "assert n_written == len(results), f'Row count mismatch: {n_written} != {len(results)}'\n"
            "print('Row count verified OK.')\n"
            "\n"
            "wb.log_decision(\n"
            "    f'scRNA-seq analysis: {N_CELLS} cells x {N_GENES} genes synthetic matrix. '\n"
            "    f'{qc_pass.sum()} cells passed QC. Embedding: {embed_label}. '\n"
            "    f'Results: {RESULTS_TABLE}.',\n"
            "    evidence=f'numpy Poisson simulation seed={RANDOM_SEED}; '\n"
            "             f'sklearn PCA n={N_PCA_COMPS}; KMeans n={N_CLUSTERS}'\n"
            ")\n"
            "print('Provenance logged.')\n"
            "print('\\nNext steps:')\n"
            "print('  - Replace synthetic data with real 10x Genomics cellranger output')\n"
            "print('  - Install umap-learn for true UMAP:  %pip install umap-learn')\n"
            "print('  - Connect RESULTS_TABLE to a Streamlit scRNA explorer dashboard')",
            "b017",
        ),
    ]
)  # end nb2


# =============================================================================
# Write files
# =============================================================================
out_dir = pathlib.Path(__file__).parent

nb1_path = out_dir / "protein_binder_design.ipynb"
nb2_path = out_dir / "single_cell_rnaseq.ipynb"

with open(nb1_path, "w") as f:
    json.dump(nb1, f, indent=1, ensure_ascii=False)

with open(nb2_path, "w") as f:
    json.dump(nb2, f, indent=1, ensure_ascii=False)

print(f"Written: {nb1_path}  ({len(nb1['cells'])} cells)")
print(f"Written: {nb2_path}  ({len(nb2['cells'])} cells)")
