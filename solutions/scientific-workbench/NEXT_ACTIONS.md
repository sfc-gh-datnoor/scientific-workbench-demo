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

The Scientific Workbench web application is a full-stack **React / Next.js application** deployed via **Snowflake App Runtime (SAR)** as an Application Service.

### Accessing the Deployed React App
1. In Snowsight, navigate to **Projects > Apps** (or **Snowflake App Runtime**).
2. Select **`SCIENTIFIC_WORKBENCH_APP`** (located in `SNOWFLAKE_APPS.PUBLIC`).
3. Click the application endpoint URL (e.g., `https://<app-id>.snowflakecomputing.app`) to open the React interface.
4. Interactively explore the 10 built-in modules: **Agent Chat, Explore, Asset Catalog, Experiments, Tool Registry, Workflows, Notebooks, Share, Portfolio, and Governance**.

### Running the React App Locally (Development)
You can also run the React web frontend locally against your Snowflake account:

```bash
cd solutions/scientific-workbench/app/
npm install
npm run dev
# Open http://localhost:3000 in your browser
```

