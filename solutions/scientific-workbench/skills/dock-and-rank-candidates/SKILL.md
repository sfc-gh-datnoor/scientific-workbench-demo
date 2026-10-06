---
name: dock-and-rank-candidates
description: Dock a supplied ligand to a protein structure with DiffDock and optionally estimate affinity with Boltz-2.
---
# Dock and rank candidates
1. Require a SMILES and either a four-character PDB ID or explicit PDB content.
2. Confirm ambiguous target names before executing.
3. Call `run_diffdock`, using 5 poses by default and never more than 20.
4. Call `run_boltz2` only when a protein sequence is available and affinity was requested.
5. Keep docking confidence separate from predicted pIC50 and do not describe either as experimental evidence.