"""Synthetic Data Generator — Scientific Workbench Demo Datasets

Generates 4 demo datasets for the Scientific Workbench:
  1. NSCLC Cohort (Persona #1 Comp Bio, #3 Clinical DS)
  2. Compound Library (Persona #2 Med Chem, #8 AI Drug Disc)
  3. Clinical Trials (Persona #3 Clinical DS)
  4. Protein Targets (Persona #4 Structural Bio)

Output: CSV files ready for Snowflake COPY INTO
Target: WORKBENCH_PROJECTS.DEMO_NSCLC, DEMO_COMPOUNDS, DEMO_CLINICAL, DEMO_STRUCTURAL

Usage:
    python generate_synthetic_data.py [--output-dir ./output]
"""

import csv
import hashlib
import os
import random
import sys
from datetime import date, timedelta

random.seed(42)
OUTPUT_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# =============================================================================
# 1. NSCLC PATIENT COHORT (200 patients)
# =============================================================================
print("Generating NSCLC patient cohort...")

KRAS_MUTATIONS = ["G12C", "G12D", "G12V", "G13D", "WT"]
KRAS_WEIGHTS = [0.35, 0.20, 0.15, 0.10, 0.20]
TREATMENTS = ["Sotorasib", "Chemo", "Combo", "Control"]
RESPONSES = ["CR", "PR", "SD", "PD"]
SMOKING = ["Never", "Former", "Current"]
GENES = [
    "KRAS",
    "TP53",
    "EGFR",
    "ALK",
    "STK11",
    "KEAP1",
    "ROS1",
    "MET",
    "BRAF",
    "ERBB2",
    "PIK3CA",
    "NRAS",
    "MAP2K1",
    "CDKN2A",
    "RB1",
    "NF1",
    "PTEN",
    "AKT1",
    "CTNNB1",
    "SMAD4",
    "ARID1A",
    "ATM",
    "BRCA2",
    "FGFR2",
    "IDH1",
    "JAK2",
    "NOTCH1",
    "PTPN11",
    "RAF1",
    "SHP2",
    "SOS1",
    "MTOR",
    "CDK4",
    "CDK6",
    "CCND1",
    "MYC",
    "BCL2",
    "VEGFA",
    "FLT3",
    "KIT",
    "PDGFRA",
    "RET",
    "NTRK1",
    "AXL",
    "DDR2",
    "FGFR1",
    "FGFR3",
    "ERBB3",
    "ERBB4",
    "TERT",
] + [f"GENE_{i:03d}" for i in range(50, 500)]  # 500 total genes

patients = []
for i in range(200):
    pid = f"PT-{i + 1:04d}"
    kras = random.choices(KRAS_MUTATIONS, KRAS_WEIGHTS)[0]
    treatment = random.choice(TREATMENTS)

    # Response correlated with mutation + treatment
    if kras == "G12C" and treatment == "Sotorasib":
        response = random.choices(RESPONSES, [0.15, 0.30, 0.30, 0.25])[0]
    elif treatment == "Combo":
        response = random.choices(RESPONSES, [0.10, 0.25, 0.35, 0.30])[0]
    else:
        response = random.choices(RESPONSES, [0.05, 0.15, 0.30, 0.50])[0]

    # PFS correlated with response
    pfs_base = {"CR": 18, "PR": 12, "SD": 7, "PD": 3}
    pfs = max(0.5, random.gauss(pfs_base[response], pfs_base[response] * 0.3))
    pfs_event = 1 if response in ("SD", "PD") or random.random() < 0.3 else 0

    patients.append(
        {
            "patient_id": pid,
            "age": random.randint(45, 82),
            "sex": random.choice(["M", "F"]),
            "smoking_status": random.choices(SMOKING, [0.25, 0.45, 0.30])[0],
            "stage": random.choice(["IIIB", "IV"]),
            "kras_mutation": kras,
            "stk11_status": random.choice(["Mutant", "WT"]),
            "pd_l1_tps": random.randint(0, 100),
            "treatment_arm": treatment,
            "response_group": response,
            "pfs_months": round(pfs, 1),
            "pfs_event": pfs_event,
            "prior_lines": random.choice([0, 0, 1, 1, 2, 3]),
        }
    )

with open(os.path.join(OUTPUT_DIR, "patients.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=patients[0].keys())
    w.writeheader()
    w.writerows(patients)

# Gene expression (long format: patient_id, gene_symbol, expression_value)
print("Generating gene expression data (100K rows)...")
expression = []
for p in patients:
    for gene in random.sample(GENES, 500):
        # Base expression + perturbation by response
        base = random.gauss(6.0, 2.0)
        if gene in ("KRAS", "EGFR", "STK11", "PTPN11") and p["response_group"] == "PD":
            base += random.gauss(1.5, 0.5)  # upregulated in resistant
        expression.append(
            {
                "patient_id": p["patient_id"],
                "gene_symbol": gene,
                "expression_value": round(max(0, base), 3),
            }
        )

with open(os.path.join(OUTPUT_DIR, "gene_expression.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["patient_id", "gene_symbol", "expression_value"])
    w.writeheader()
    w.writerows(expression)

# =============================================================================
# 2. COMPOUND LIBRARY (1000 compounds, 5000 assay results)
# =============================================================================
print("Generating compound library...")

SCAFFOLDS = [
    "c1ccc(NC(=O)c2ccc",
    "c1ccncc1NC(=O)",
    "CC(=O)Nc1ccc(",
    "O=C(Nc1ccccc1)",
    "c1ccc2c(c1)cc(",
    "CCOc1ccc(NC(=O)",
    "Fc1ccc(NC(=O)c2",
    "Clc1ccc(NC(",
    "c1ccc(-c2nccn2)cc1",
    "COc1ccc(CC(=O)Nc2",
]
TARGETS = ["KRAS_G12C", "JAK2", "EGFR", "ALK", "MET", "BRAF_V600E", "CDK4_6", "BTK", "PI3K_alpha"]
PROJECTS = ["KRAS_P1", "JAK2_P2", "EGFR_P3", "CDK_P4"]

compounds = []
for i in range(1000):
    cid = f"CPD-{i + 1:05d}"
    scaffold = random.choice(SCAFFOLDS)
    # Generate pseudo-SMILES (not chemically valid but structurally consistent)
    smiles = scaffold + ")" * random.randint(1, 3) + random.choice(["F", "Cl", "N", "O", "C"])
    inchikey = (
        hashlib.md5(smiles.encode()).hexdigest()[:14].upper()
        + "-"
        + hashlib.md5(cid.encode()).hexdigest()[:10].upper()
        + "-N"
    )

    mw = round(random.gauss(420, 80), 1)
    logp = round(random.gauss(3.0, 1.2), 2)
    compounds.append(
        {
            "compound_id": cid,
            "smiles": smiles,
            "inchikey": inchikey,
            "project": random.choice(PROJECTS),
            "series": f"Series_{random.randint(1, 20)}",
            "mw": mw,
            "logp": logp,
            "hbd": random.randint(0, 4),
            "hba": random.randint(1, 8),
            "tpsa": round(random.gauss(85, 30), 1),
            "rotatable_bonds": random.randint(2, 10),
        }
    )

with open(os.path.join(OUTPUT_DIR, "compounds.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=compounds[0].keys())
    w.writeheader()
    w.writerows(compounds)

# Assay results
assays = []
for i in range(5000):
    cpd = random.choice(compounds)
    target = random.choice(TARGETS)
    ic50 = round(10 ** random.gauss(2, 1.5), 1)  # nM, log-normal
    assays.append(
        {
            "assay_id": f"ASY-{i + 1:06d}",
            "compound_id": cpd["compound_id"],
            "target": target,
            "assay_type": "IC50",
            "value_nm": ic50,
            "selectivity_ratio": round(random.gauss(10, 5), 1) if random.random() > 0.5 else None,
            "experiment_date": (date(2025, 1, 1) + timedelta(days=random.randint(0, 500))).isoformat(),
        }
    )

with open(os.path.join(OUTPUT_DIR, "assays.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=assays[0].keys())
    w.writeheader()
    w.writerows(assays)

# =============================================================================
# 3. CLINICAL TRIAL RECORDS (200 trials, KRAS/NSCLC focused)
# =============================================================================
print("Generating clinical trials...")

SPONSORS = [
    "Amgen",
    "Mirati",
    "Revolution Medicines",
    "Sanofi",
    "AstraZeneca",
    "Roche",
    "Merck",
    "Pfizer",
    "Bristol-Myers Squibb",
    "Eli Lilly",
]
PHASES = ["Phase 1", "Phase 1/2", "Phase 2", "Phase 2/3", "Phase 3"]
STATUSES = ["Recruiting", "Active, not recruiting", "Completed", "Terminated"]
CONDITIONS_POOL = [
    "Non-Small Cell Lung Cancer",
    "Colorectal Cancer",
    "Pancreatic Cancer",
    "Solid Tumors",
    "KRAS G12C Mutant",
    "Advanced NSCLC",
]
DRUGS_POOL = [
    "Sotorasib",
    "Adagrasib",
    "Divarasib",
    "JDQ443",
    "GDC-6036",
    "RMC-6236",
    "Pembrolizumab",
    "Docetaxel",
    "Carboplatin",
    "SHP2i",
]

trials = []
for i in range(200):
    nct = f"NCT{random.randint(10000000, 99999999)}"
    start = date(2020, 1, 1) + timedelta(days=random.randint(0, 1800))
    trials.append(
        {
            "nct_id": nct,
            "brief_title": f"{random.choice(DRUGS_POOL)} in {random.choice(CONDITIONS_POOL)}: Phase {random.choice(['1', '2', '3'])} Study",
            "overall_status": random.choice(STATUSES),
            "phase": random.choice(PHASES),
            "start_date": start.isoformat(),
            "sponsor": random.choice(SPONSORS),
            "condition": random.choice(CONDITIONS_POOL),
            "intervention": random.choice(DRUGS_POOL),
            "enrollment": random.randint(20, 500),
        }
    )

with open(os.path.join(OUTPUT_DIR, "trials.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=trials[0].keys())
    w.writeheader()
    w.writerows(trials)

# =============================================================================
# 4. PROTEIN TARGETS (50 targets with sequences)
# =============================================================================
print("Generating protein targets...")

AMINO_ACIDS = "ACDEFGHIKLMNPQRSTVWY"
TARGET_NAMES = [
    ("KRAS", "GTPase KRas", 189),
    ("EGFR", "Epidermal growth factor receptor", 1210),
    ("ALK", "ALK tyrosine kinase", 1620),
    ("BRAF", "Serine/threonine-protein kinase B-Raf", 766),
    ("JAK2", "Tyrosine-protein kinase JAK2", 1132),
    ("MET", "Hepatocyte growth factor receptor", 1390),
    ("PIK3CA", "PI3-kinase p110-alpha", 1068),
    ("CDK4", "Cyclin-dependent kinase 4", 303),
    ("CDK6", "Cyclin-dependent kinase 6", 326),
    ("BTK", "Bruton tyrosine kinase", 659),
    ("FGFR2", "Fibroblast growth factor receptor 2", 821),
    ("RET", "Proto-oncogene RET", 1114),
    ("SHP2", "Tyrosine-protein phosphatase SHP-2", 593),
    ("SOS1", "Son of sevenless homolog 1", 1333),
    ("PTPN11", "Tyrosine-protein phosphatase non-receptor type 11", 593),
]

proteins = []
for gene, name, length in TARGET_NAMES:
    seq = "".join(random.choices(AMINO_ACIDS, k=min(length, 500)))  # truncate for demo
    proteins.append(
        {
            "gene_symbol": gene,
            "protein_name": name,
            "uniprot_id": f"P{random.randint(10000, 99999)}",
            "sequence": seq,
            "length": length,
            "pdb_ids": f"{random.choice(['6OIM', '7RPZ', '5UO9', '6VJJ', '3GFT'])}",
            "organism": "Homo sapiens",
            "druggability_score": round(random.gauss(0.7, 0.15), 2),
        }
    )

with open(os.path.join(OUTPUT_DIR, "proteins.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=proteins[0].keys())
    w.writeheader()
    w.writerows(proteins)

# =============================================================================
# Summary
# =============================================================================
print(f"""
=== Synthetic Data Generated ===
Output directory: {OUTPUT_DIR}

Files:
  patients.csv           {len(patients)} patients (NSCLC cohort)
  gene_expression.csv    {len(expression)} expression measurements
  compounds.csv          {len(compounds)} compounds
  assays.csv             {len(assays)} assay results
  trials.csv             {len(trials)} clinical trials
  proteins.csv           {len(proteins)} protein targets

Load into Snowflake:
  PUT file://{OUTPUT_DIR}/*.csv @WORKBENCH_PROJECTS.DEMO_NSCLC.DATA_STAGE;
  COPY INTO WORKBENCH_PROJECTS.DEMO_NSCLC.PATIENTS FROM @DATA_STAGE/patients.csv ...
""")
