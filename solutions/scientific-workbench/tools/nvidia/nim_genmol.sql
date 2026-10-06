-- =============================================================================
-- tools/nvidia/nim_genmol.sql
-- GenMol NIM wrapper — de novo molecule generation
-- =============================================================================
-- SPCS endpoint path UNKNOWN — read from container /openapi.json after deployment.
-- SPCS SPECIAL: GenMol requires huggingface.co egress for tokenizer at model-init.
-- Dual-mode: checks NIM_ENDPOINTS table for SPCS URL, falls back to hosted API.
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_GENMOL(
    seed_smiles  VARCHAR,
    n_samples    INT,
    temperature  FLOAT,
    output_table VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'requests', 'pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key' = SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT = 'TOOL:{"display_name":"GenMol (Molecule Generation)","description":"Generate novel drug-like molecules using NVIDIA GenMol NIM. Accepts a seed SMILES and returns generated SMILES with generation confidence. Supports scaffold decoration and de novo generation.","domains":"chemistry,drug-discovery,generative","params":{"seed_smiles":"STRING","n_samples":"INT","temperature":"FLOAT","output_table":"STRING"},"return_type":"VARCHAR","example":"CALL CATALOG.RUN_GENMOL(seed_smiles, 100, 0.7, output_table)"}'
AS
$$
import json, requests, _snowflake, pandas as pd
from snowflake.snowpark.context import get_active_session

HOSTED_ENDPOINT = 'https://health.api.nvidia.com/v1/biology/nvidia/genmol/generate'

def _get_endpoint(session):
    try:
        rows = session.sql(
            "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
            "WHERE NIM_NAME = 'genmol' AND DEPLOYMENT_MODE = 'spcs' LIMIT 1"
        ).collect()
        # An SPCS row may hold a bare path (see NIM_ENDPOINTS.NOTES); it is only a
        # usable endpoint once it is an absolute URL. Otherwise fall back to hosted.
        if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
            return rows[0][0]
    except Exception:
        pass
    return HOSTED_ENDPOINT

def run(session, seed_smiles: str, n_samples: int, temperature: float, output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    endpoint = _get_endpoint(session)

    payload = {
        'smiles': seed_smiles,
        'num_molecules': min(n_samples, 500),
        'temperature': max(0.1, min(temperature, 2.0)),
        'unique': True
    }

    response = requests.post(
        endpoint,
        headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
        json=payload, timeout=120
    )
    response.raise_for_status()
    data = response.json()

    molecules = data.get('molecules', [])
    if not molecules:
        return f'WARNING: No molecules generated. Response: {json.dumps(data)[:200]}'

    rows = []
    for m in molecules:
        smiles = m.get('smiles') or m.get('structure') or ''
        if not smiles:
            continue
        score  = m.get('score', 0.0)
        rows.append({'SMILES': smiles, 'CONFIDENCE': float(score),
                     'SEED_SMILES': seed_smiles, 'TEMPERATURE': temperature})

    result_df = pd.DataFrame(rows)
    result_sp = session.create_dataframe(result_df)
    result_sp.write.mode('overwrite').save_as_table(output_table)
    return f'SUCCESS: Generated {len(rows)} molecules from seed. Results in {output_table}'
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_genmol', 'GenMol — Molecule Generation',
    'Generate novel drug-like molecules using NVIDIA GenMol NIM. Supports seed-guided generation, scaffold decoration, and temperature control.',
    'chemistry,drug-discovery,generative', 'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_GENMOL',
    '{"seed_smiles":"STRING","n_samples":"INT","temperature":"FLOAT","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_GENMOL(seed_smiles, 100, 0.7, output_table)'
);
