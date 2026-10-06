-- =============================================================================
-- tools/nvidia/nim_diffdock.sql
-- DiffDock NIM wrapper — molecular docking
-- =============================================================================
-- SPCS endpoint path UNKNOWN — read from container /openapi.json after deployment.
-- Image: 15.33 GiB compressed (largest after RFdiffusion). GPU: L40S (conservative).
-- Dual-mode: checks NIM_ENDPOINTS table for SPCS URL, falls back to hosted API.
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_DIFFDOCK("SMILES" VARCHAR, "TARGET_PDB" VARCHAR, "N_POSES" NUMBER(38,0), "OUTPUT_TABLE" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests','pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key'=SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT='TOOL:{\"display_name\":\"DiffDock — Molecular Docking\",\"description\":\"Predict 3D binding poses of a ligand against a protein target using DiffDock NIM. Returns ranked poses with confidence scores.\",\"domains\":\"structural,drug-discovery\",\"params\":{\"smiles\":\"STRING\",\"target_pdb\":\"STRING\",\"n_poses\":\"INT\",\"output_table\":\"STRING\"},\"return_type\":\"VARCHAR\",\"example\":\"CALL CATALOG.RUN_DIFFDOCK(CC(=O)Oc1ccccc1C(=O)O, 1CRN, 5, output_table)\"}'
EXECUTE AS OWNER
AS
$$
import json, requests, _snowflake, pandas as pd

# VERIFIED 2026-09-01 against the live hosted API.
#   endpoint : /v1/biology/mit/diffdock   (publisher is mit, not nvidia)
#   request  : ligand_file_type is REQUIRED and must be one of mol2 | sdf | txt.
#              A SMILES string is sent as 'txt'. Omitting the field, or sending
#              'smiles', is rejected with an enum validation error.
#   response : ligand_positions[], position_confidence[] (these were already correct)
HOSTED_ENDPOINT = 'https://health.api.nvidia.com/v1/biology/mit/diffdock'

def _get_endpoint(session):
    try:
        rows = session.sql(
            "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
            "WHERE NIM_NAME = 'diffdock' AND DEPLOYMENT_MODE = 'spcs' LIMIT 1"
        ).collect()
        if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
            return rows[0][0]
    except Exception:
        pass
    return HOSTED_ENDPOINT

def run(session, smiles: str, target_pdb: str, n_poses: int, output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    endpoint = _get_endpoint(session)

    ref = (target_pdb or '').strip()
    if len(ref) == 4 and ref.isalnum():
        r = requests.get(f'https://files.rcsb.org/download/{ref.upper()}.pdb', timeout=60)
        r.raise_for_status()
        pdb_content = r.text
    elif ref.startswith('@'):
        rws = session.sql(f"SELECT $1 FROM {ref}").collect()
        pdb_content = '\\n'.join([str(x[0]) for x in rws])
    elif 'ATOM' in ref:
        pdb_content = ref
    else:
        return 'ERROR: Pass a 4-character PDB ID, an @stage path, or raw PDB text.'

    poses = max(1, min(int(n_poses or 1), 20))
    payload = {
        'ligand': smiles,
        'ligand_file_type': 'txt',
        'protein': pdb_content,
        'num_poses': poses,
        'time_divisions': 20,
        'steps': 18
    }

    response = requests.post(
        endpoint,
        headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
        json=payload, timeout=300
    )
    if response.status_code >= 400:
        raise RuntimeError(f'NIM call failed: HTTP {response.status_code} at {endpoint} :: {response.text[:500]}')
    data = response.json()

    if str(data.get('status', '')).lower() not in ('', 'success'):
        return f"WARNING: DiffDock status={data.get('status')} details={str(data.get('details'))[:300]}"

    ligand_positions = data.get('ligand_positions') or []
    position_confidence = data.get('position_confidence') or []

    rows = []
    for i, pose in enumerate(ligand_positions):
        conf = None
        if i < len(position_confidence):
            try:
                conf = float(position_confidence[i])
            except (TypeError, ValueError):
                conf = None
        rows.append({
            'SMILES': smiles,
            'TARGET_PDB': ref.upper()[:10],
            'POSE_IDX': i,
            'CONFIDENCE': conf,
            'POSE_SDF': (pose if isinstance(pose, str) else json.dumps(pose))[:15000]
        })

    if not rows:
        return f'WARNING: No poses returned. Response keys: {list(data.keys())}'

    result_sp = session.create_dataframe(pd.DataFrame(rows))
    result_sp.write.mode('overwrite').save_as_table(output_table)
    best = max([r['CONFIDENCE'] for r in rows if r['CONFIDENCE'] is not None], default=None)
    best_str = f', best confidence {best:.3f}' if best is not None else ''
    return f'SUCCESS: Generated {len(rows)} poses{best_str}. Results in {output_table}'
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_diffdock', 'DiffDock — Molecular Docking',
    'Predict binding poses for a small molecule against a protein target using DiffDock NIM.',
    'structural,docking,drug-discovery', 'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_DIFFDOCK',
    '{"smiles":"STRING","target_pdb":"STRING","n_poses":"INT","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_DIFFDOCK(smiles, 6OIM, 5, output_table)'
);
