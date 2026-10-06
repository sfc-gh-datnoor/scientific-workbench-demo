---
name: generate-and-filter-molecules
description: Generate molecules from a seed SMILES with GenMol, then assess validity and drug-like descriptors.
---
# Generate and filter molecules
1. Require a non-empty seed SMILES and bound sample count to 1-500.
2. Use temperature 0.7 unless the user specifies a value between 0.1 and 2.0.
3. Call `run_genmol` into a controlled results table.
4. Explain required sanitization, structural-alert screening, and descriptor checks.
5. Do not call a generated molecule safe, active, selective, or synthesizable from generation confidence.