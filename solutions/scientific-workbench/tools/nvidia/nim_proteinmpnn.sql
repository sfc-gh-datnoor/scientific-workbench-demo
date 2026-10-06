-- =============================================================================
-- tools/nvidia/nim_proteinmpnn.sql
-- ProteinMPNN NIM — inverse folding (backbone → sequences)
-- =============================================================================
-- SPCS endpoint path UNKNOWN — read from container /openapi.json after deployment.
-- Image: 8.60 GiB compressed (smallest NIM). GPU: A10G (GPU_NV_S).
-- NGC click-through license already accepted on this org (HTTP 200).
-- Dual-mode: checks NIM_ENDPOINTS table for SPCS URL, falls back to hosted API.
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_PROTEINMPNN("BACKBONE_PDB_STAGE_PATH" VARCHAR, "N_SAMPLES" NUMBER(38,0), "TEMPERATURE" FLOAT, "OUTPUT_TABLE" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests','pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key'=SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT='TOOL:{\"display_name\":\"ProteinMPNN — Sequence Design\",\"description\":\"Design amino acid sequences for a given protein backbone using ProteinMPNN NIM. Inverse folding: takes a PDB backbone and returns designed sequences with recovery scores.\",\"domains\":\"structural,protein-engineering\",\"params\":{\"backbone_pdb_stage_path\":\"STRING\",\"n_samples\":\"INT\",\"temperature\":\"FLOAT\",\"output_table\":\"STRING\"},\"return_type\":\"VARCHAR\",\"example\":\"CALL CATALOG.RUN_PROTEINMPNN(1CRN, 20, 0.1, output_table)\"}'
EXECUTE AS OWNER
AS
$$
import json, requests, _snowflake, pandas as pd

# VERIFIED 2026-09-01 against the live hosted API.
#   endpoint : /v1/biology/ipd/proteinmpnn/predict   (publisher is ipd, not nvidia)
#   request  : input_pdb (NOT pdb_content), num_seq_per_target, sampling_temp as a LIST
#   response : mfasta (multi-FASTA string, NOT a 'sequences' list), scores, probs
HOSTED_ENDPOINT = 'https://health.api.nvidia.com/v1/biology/ipd/proteinmpnn/predict'

def _get_endpoint(session):
    try:
        rows = session.sql(
            "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
            "WHERE NIM_NAME = 'proteinmpnn' AND DEPLOYMENT_MODE = 'spcs' LIMIT 1"
        ).collect()
        if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
            return rows[0][0]
    except Exception:
        pass
    return HOSTED_ENDPOINT

def _load_pdb(session, ref):
    """Accept a 4-char PDB ID, an @stage path, or raw PDB text."""
    ref = (ref or '').strip()
    if len(ref) == 4 and ref.isalnum():
        r = requests.get(f'https://files.rcsb.org/download/{ref.upper()}.pdb', timeout=60)
        r.raise_for_status()
        return r.text
    if ref.startswith('@'):
        rows = session.sql(f"SELECT $1 FROM {ref}").collect()
        return '\\n'.join([str(x[0]) for x in rows])
    return ref

def _parse_mfasta(mfasta):
    """ProteinMPNN returns designs as a multi-FASTA string."""
    out, header, buf = [], None, []
    for line in (mfasta or '').splitlines():
        line = line.strip()
        if line.startswith('>'):
            if header is not None:
                out.append((header, ''.join(buf)))
            header, buf = line[1:], []
        elif line:
            buf.append(line)
    if header is not None:
        out.append((header, ''.join(buf)))
    return [(h, s) for h, s in out if s]

def run(session, backbone_pdb_stage_path: str, n_samples: int, temperature: float, output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    endpoint = _get_endpoint(session)

    pdb_content = _load_pdb(session, backbone_pdb_stage_path)
    if not pdb_content or 'ATOM' not in pdb_content:
        return 'ERROR: could not obtain PDB content. Pass a 4-char PDB ID, an @stage path, or raw PDB text.'

    temp = max(0.01, min(float(temperature or 0.1), 1.0))
    payload = {
        'input_pdb': pdb_content,
        'num_seq_per_target': max(1, min(int(n_samples or 1), 128)),
        'sampling_temp': [temp]
    }

    response = requests.post(
        endpoint,
        headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
        json=payload, timeout=300
    )
    if response.status_code >= 400:
        raise RuntimeError(f'NIM call failed: HTTP {response.status_code} at {endpoint} :: {response.text[:500]}')
    data = response.json()

    records = _parse_mfasta(data.get('mfasta', ''))
    scores = data.get('scores') or []
    if not isinstance(scores, list):
        scores = [scores]

    rows = []
    for i, (header, seq) in enumerate(records):
        sc = None
        if i < len(scores):
            try:
                sc = float(scores[i])
            except (TypeError, ValueError):
                sc = None
        rows.append({'SEQUENCE': seq, 'RECOVERY_SCORE': sc, 'SAMPLE_IDX': i, 'FASTA_HEADER': str(header)[:300]})

    if not rows:
        return f'WARNING: No sequences returned. Raw keys: {list(data.keys())}'

    result_sp = session.create_dataframe(pd.DataFrame(rows))
    result_sp.write.mode('overwrite').save_as_table(output_table)
    return f'SUCCESS: Designed {len(rows)} sequences. Results in {output_table}'
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_proteinmpnn', 'ProteinMPNN — Sequence Design',
    'Design amino acid sequences for a given protein backbone using ProteinMPNN NIM.',
    'structural,protein-engineering', 'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_PROTEINMPNN',
    '{"backbone_pdb_stage_path":"STRING","n_samples":"INT","temperature":"FLOAT","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_PROTEINMPNN(@stage/backbone.pdb, 20, 0.1, output_table)'
);
