---
name: design-protein-binder
description: Design protein binders with RFdiffusion and ProteinMPNN followed by structure validation.
---
# Design a protein binder
1. Require a valid target PDB and explicit hotspot residues; never invent hotspots.
2. Call `run_rfdiffusion` with bounded binder length and design count.
3. Call `run_proteinmpnn` for each accepted backbone.
4. Validate designed sequences with the narrowest applicable structure model.
5. Preserve every intermediate result reference and report failures per stage.
6. Do not claim binding, specificity, expression, or safety without experimental evidence.