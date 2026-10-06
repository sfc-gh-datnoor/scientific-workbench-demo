---
name: build-and-evaluate-msa
description: Build a multiple-sequence alignment for an amino-acid sequence with MSA Search.
---
# Build and evaluate an MSA
1. Normalize input to uppercase and reject empty or clearly nucleotide-only input.
2. Generate a result table under `SCIENTIFIC_WORKBENCH.RESULTS` and call `run_msa_search` once.
3. Report sequence count, database, format, and output location.
4. Do not claim that alignment depth guarantees structural accuracy.