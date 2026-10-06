-- =============================================================================
-- tools/nvidia/nim_rfdiffusion.sql
-- RFdiffusion NIM — de novo protein backbone generation
-- =============================================================================
-- SPCS endpoint path UNKNOWN — image mirrored (16.37 GiB, largest NIM) and
-- digest verified, but NEVER SERVED. Read endpoint from /openapi.json after deploy.
-- GPU: L40S (GPU_L40S_G1_16) — likely requirement, UNTESTED.
-- Dual-mode: checks NIM_ENDPOINTS table for SPCS URL, falls back to hosted API.
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_RFDIFFUSION("TARGET_PDB" VARCHAR, "HOTSPOT_RESIDUES" VARCHAR, "BINDER_LENGTH" NUMBER(38,0), "N_DESIGNS" NUMBER(38,0), "OUTPUT_TABLE" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests','pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key'=SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT='TOOL:{\"display_name\":\"RFdiffusion — Backbone Design\",\"description\":\"Generate de novo protein backbone scaffolds for binder design using RFdiffusion NIM. Specify hotspot residues on the target surface to guide binder design.\",\"domains\":\"structural,protein-engineering\",\"params\":{\"target_pdb\":\"STRING\",\"hotspot_residues\":\"STRING\",\"binder_length\":\"INT\",\"n_designs\":\"INT\",\"output_table\":\"STRING\"},\"return_type\":\"VARCHAR\",\"example\":\"CALL CATALOG.RUN_RFDIFFUSION(1CRN, A20, 40, 2, output_table)\"}'
EXECUTE AS OWNER
AS
$$
import json, requests, _snowflake, pandas as pd

# VERIFIED 2026-09-01 against the live hosted API.
#   endpoint : /v1/biology/ipd/rfdiffusion/generate  (publisher is ipd, not nvidia)
#   request  : input_pdb + contigs (REQUIRED) + hotspot_res + diffusion_steps.
#              There is no num_designs/binder_length/protein field; 'contigs' encodes
#              the binder length, and the API returns ONE design per call, so N designs
#              require N calls.
#   response : output_pdb (a single PDB string), elapsed_ms. Not 'backbones'/'confidence'.
HOSTED_ENDPOINT = 'https://health.api.nvidia.com/v1/biology/ipd/rfdiffusion/generate'

def _get_endpoint(session):
    try:
        rows = session.sql(
            "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
            "WHERE NIM_NAME = 'rfdiffusion' AND DEPLOYMENT_MODE = 'spcs' LIMIT 1"
        ).collect()
        if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
            return rows[0][0]
    except Exception:
        pass
    return HOSTED_ENDPOINT

def _first_chain_residues(pdb_text):
    """Return (chain_id, sorted list of residue numbers present) for the first
    chain seen in ATOM records.

    RFdiffusion validates every residue named in a contig against the supplied
    PDB. Crystal structures routinely omit disordered residues, so a naive
    min-max range walks straight into those holes: 6OIM chain A spans 0-169 but
    has no 105, 106 or 107, and 'A0-169' is rejected with
    HTTP 422 "Residue A105 is not in pdb file."
    """
    chain, present = None, []
    for line in pdb_text.splitlines():
        if line.startswith('ATOM'):
            c = line[21:22].strip() or 'A'
            try:
                r = int(line[22:26])
            except ValueError:
                continue
            if chain is None:
                chain = c
            if c != chain:
                break
            present.append(r)
    return chain, sorted(set(present))

def _contig_segments(chain, present):
    """Collapse residue numbers into contiguous RFdiffusion contig segments.

    [0..104, 108..169] on chain A becomes 'A0-104/A108-169', so every residue
    referenced is one the PDB actually contains.
    """
    if not present:
        return None
    runs, start, prev = [], present[0], present[0]
    for r in present[1:]:
        if r == prev + 1:
            prev = r
            continue
        runs.append((start, prev))
        start, prev = r, r
    runs.append((start, prev))
    return '/'.join(f'{chain}{a}-{b}' for a, b in runs)

def run(session, target_pdb: str, hotspot_residues: str, binder_length: int,
        n_designs: int, output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    endpoint = _get_endpoint(session)

    ref = (target_pdb or '').strip()
    if len(ref) == 4 and ref.isalnum():
        r = requests.get(f'https://files.rcsb.org/download/{ref.upper()}.pdb', timeout=60)
        r.raise_for_status()
        pdb_content = r.text
    elif 'ATOM' in ref:
        pdb_content = ref
    else:
        return 'ERROR: Pass a 4-character PDB ID or raw PDB text.'

    chain, present = _first_chain_residues(pdb_content)
    if chain is None or not present:
        return 'ERROR: no ATOM records found in the supplied PDB.'

    target_contig = _contig_segments(chain, present)
    blen = max(10, min(int(binder_length or 40), 300))
    contigs = f'{target_contig}/0 {blen}-{blen}'

    # A hotspot the PDB does not contain is rejected the same way a bad contig is,
    # so drop unknown ones and say so rather than failing the whole request.
    present_set = set(present)
    hotspots, dropped = [], []
    for h in (hotspot_residues or '').split(','):
        h = h.strip()
        if not h:
            continue
        digits = ''.join(ch for ch in h if ch.isdigit())
        if digits and int(digits) not in present_set:
            dropped.append(h)
        else:
            hotspots.append(h)

    n = max(1, min(int(n_designs or 1), 10))
    rows, errors = [], []
    for i in range(n):
        payload = {'input_pdb': pdb_content, 'contigs': contigs, 'diffusion_steps': 15}
        if hotspots:
            payload['hotspot_res'] = hotspots
        resp = requests.post(
            endpoint,
            headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
            json=payload, timeout=300
        )
        if resp.status_code >= 400:
            errors.append(f'design {i}: HTTP {resp.status_code} {resp.text[:200]}')
            continue
        d = resp.json()
        out_pdb = d.get('output_pdb') or ''
        if not out_pdb:
            errors.append(f'design {i}: no output_pdb, keys={list(d.keys())}')
            continue
        rows.append({
            'BACKBONE_PDB': out_pdb[:15000],
            'ELAPSED_MS': float(d.get('elapsed_ms') or 0.0),
            'DESIGN_IDX': i,
            'TARGET_PDB': ref.upper()[:10],
            'BINDER_LENGTH': blen,
            'CONTIGS': contigs
        })

    if not rows:
        return 'ERROR: No backbones generated. ' + ' | '.join(errors[:3])

    result_sp = session.create_dataframe(pd.DataFrame(rows))
    result_sp.write.mode('overwrite').save_as_table(output_table)
    suffix = f' ({len(errors)} failed)' if errors else ''
    if dropped:
        suffix += f' (hotspots absent from PDB, ignored: {",".join(dropped)})'
    return f'SUCCESS: Generated {len(rows)} backbones using contigs {contigs}{suffix}. Results in {output_table}'
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_rfdiffusion', 'RFdiffusion — Backbone Design',
    'Generate de novo protein backbone scaffolds for binder design against a target surface patch.',
    'structural,protein-engineering', 'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_RFDIFFUSION',
    '{"target_pdb":"STRING","hotspot_residues":"STRING","binder_length":"INT","n_designs":"INT","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_RFDIFFUSION(6OIM, A12,A45, 80, 10, output_table)'
);
