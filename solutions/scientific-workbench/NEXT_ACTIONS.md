# Next Actions: Snowflake Scientific Workbench

Follow these steps to verify your installation, explore scientific personas, and run live discovery workflows.

---

## 1. Verify Deployment

Run the following SQL queries to ensure all platform assets and tools are active:

```sql
-- 1. Check registered active tools (Expected: 23)
SELECT COUNT(*) AS active_tools
FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
WHERE STATUS = 'active';

-- 2. Test Discovery Agent execution
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
  'SCIENTIFIC_WORKBENCH.CATALOG.DISCOVERY_AGENT',
  '{"messages":[{"role":"user","content":[{"type":"text","text":"What tools are available in the workbench?"}]}]}',
  TRUE
);
```

---

## 2. Interactive Discovery Queries by Persona

Test the Discovery Agent with representative domain questions across the 6 life sciences roles:

### Computational Biologist
```
"Which genes are significantly differentially expressed in KRAS G12C tumors compared to wild-type?"
"Run pathway enrichment on the top upregulated genes in cohort A."
```

### Medicinal Chemist
```
"Generate 5 analogs of aspirin using GenMol and evaluate their drug-likeness (QED and LogP)."
"Optimize this SMILES structure for improved solubility using MolMIM: CC(=O)Oc1ccccc1C(=O)O"
```

### Structural Biologist
```
"Predict the complex structure and binding affinity of PD-L1 with small molecule ligand using Boltz-2."
"Design a 50-residue de novo protein backbone scaffold targeting KRAS G12C using RFdiffusion."
```

### Clinical Data Scientist
```
"What is the progression-free survival (PFS) rate for patients on Sotorasib with KRAS G12C mutations?"
"Show me the patient demographics and response rates across all Phase 2 clinical trials in the catalog."
```

### AI Drug Discovery Scientist
```
"Run the end-to-end drug discovery pipeline starting with seed molecule imatinib against BCR-ABL target."
```

---

## 3. Launching the Web Application

To access the Next.js Snowflake App Runtime application:
1. In Snowsight, navigate to **Projects > Streamlit / Apps**.
2. Select **`SNOWFLAKE_APPS.PUBLIC.SCIENTIFIC_WORKBENCH_APP`**.
3. Open the web interface to interactively explore the Chat, Asset Catalog, Experiments, Tool Registry, and Governance logs.
