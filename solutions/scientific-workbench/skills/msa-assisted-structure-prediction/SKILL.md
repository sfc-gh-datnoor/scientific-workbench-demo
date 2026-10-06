---
name: msa-assisted-structure-prediction
description: Predict a protein or biomolecular-complex structure with MSA context using MSA Search followed by OpenFold3.
---
# MSA-assisted structure prediction
1. Validate the protein sequence and optional ligand SMILES.
2. Run `run_msa_search` and retain its output reference.
3. Run `run_openfold3` with typed molecule objects, using a query-only MSA only when no alignment is returned.
4. Report pLDDT, pTM, ipTM, MSA depth, structure format, and output references.
5. Treat low confidence as uncertainty, not negative biological evidence.