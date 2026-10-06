---
name: generate-genomic-sequences
description: Generate or extend DNA or RNA sequences with Evo2.
---
# Generate genomic sequences
1. Confirm that the input contains an explicit DNA or RNA prompt and a requested token count.
2. Reject amino-acid sequences and clinical interpretation requests.
3. Keep `n_tokens` between 1 and 1024; use 64 when unspecified.
4. Generate a safe result table under `SCIENTIFIC_WORKBENCH.RESULTS` and call `run_evo2` once.
5. Report generated length, elapsed time, result table, and the need for biological validation.