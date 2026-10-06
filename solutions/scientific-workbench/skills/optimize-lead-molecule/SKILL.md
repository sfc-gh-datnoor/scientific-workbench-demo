---
name: optimize-lead-molecule
description: Optimize a seed molecule for QED or penalized LogP with MolMIM.
---
# Optimize a lead molecule
1. Require a seed SMILES and map the requested objective to QED or penalized LogP.
2. Use 10 iterations and 5 samples by default and enforce procedure bounds.
3. Call `run_molmim` into a controlled results table.
4. Report the objective, scores, similarity constraint, and output location.
5. State that one optimized property does not establish potency, ADMET, novelty, or synthetic feasibility.