-- =============================================================================
-- tools/nvidia/nim_boltz2.sql
-- Boltz-2 NIM — co-folding + binding affinity prediction
-- =============================================================================
-- VERIFIED on SPCS (2026-08-26): L40S GPU_L40S_G1_16, 2.3 s warm inference.
--
-- DUAL-MODE: Checks NIM_ENDPOINTS config table for SPCS service URL.
--   Falls back to hosted API if no SPCS entry found.
--   SPCS endpoint: POST /biology/mit/boltz2/predict
--   Hosted endpoint: POST /v1/biology/mit/boltz2/predict
--
-- ENDPOINT VERIFIED 2026-09-01 by probing the live hosted API with a valid key.
-- The previous value, /v1/biology/nvidia/boltz-1, returns 404 and is dead.
-- General rule confirmed across all 11 NIMs: the hosted route is
-- 'https://health.api.nvidia.com/v1' + the container's own route, and the
-- publisher segment is the model's real publisher (mit, ipd, colabfold,
-- openfold, arc, nvidia), NOT 'nvidia' for everything.
--
-- API CONTRACT (from container /openapi.json, NOT from documentation):
--   Request: {polymers: [{id, molecule_type, sequence}], ligands: [{id, smiles, predict_affinity}]}
--   - predict_affinity is a LIGAND property. At request root = silent failure (no error, no affinity).
--   - molecule_type enum: dna | rna | protein
--   - Max: 12 polymers, 20 ligands
--   Response: mmCIF structure (not PDB), confidence_scores, complex_plddt, complex_iplddt,
--             affinity_pic50, affinity_pred_value, affinity_probability_binary
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_BOLTZ2("PROTEIN_SEQUENCE" VARCHAR, "LIGAND_SMILES" VARCHAR, "TASK" VARCHAR, "OUTPUT_TABLE" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests','pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key'=SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT='TOOL:{\"display_name\":\"Boltz-2 — Structure + Affinity\",\"description\":\"Predict biomolecular structures and binding affinity using Boltz-2 NIM. Supports protein-only, protein-ligand, and protein-protein complexes. Returns mmCIF structure and confidence scores (pLDDT, ipLDDT, pIC50). Verified on SPCS L40S.\",\"domains\":\"structural,affinity,drug-discovery\",\"params\":{\"protein_sequence\":\"STRING\",\"ligand_smiles\":\"STRING\",\"task\":\"STRING\",\"output_table\":\"STRING\"},\"return_type\":\"VARCHAR\",\"example\":\"CALL CATALOG.RUN_BOLTZ2(sequence, smiles, complex, output_table)\"}'
EXECUTE AS OWNER
AS
$$
import json, requests, _snowflake, pandas as pd
from snowflake.snowpark.context import get_active_session

HOSTED_ENDPOINT = 'https://health.api.nvidia.com/v1/biology/mit/boltz2/predict'
SPCS_PATH = '/biology/mit/boltz2/predict'

def _get_endpoint(session):
    """Check NIM_ENDPOINTS table for SPCS service URL; fall back to hosted API."""
    try:
        rows = session.sql(
            "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
            "WHERE NIM_NAME = 'boltz2' AND DEPLOYMENT_MODE = 'spcs' LIMIT 1"
        ).collect()
        if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
            return rows[0][0]
    except Exception:
        pass
    return HOSTED_ENDPOINT

def run(session, protein_sequence: str, ligand_smiles: str, task: str, output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    endpoint = _get_endpoint(session)

    polymers = [{'id': 'A', 'molecule_type': 'protein', 'sequence': protein_sequence}]
    payload = {'polymers': polymers}

    if ligand_smiles and task in ('affinity', 'complex'):
        payload['ligands'] = [{'id': 'L', 'smiles': ligand_smiles, 'predict_affinity': True}]
    elif ligand_smiles and task == 'structure':
        payload['ligands'] = [{'id': 'L', 'smiles': ligand_smiles}]

    headers = {'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'}

    response = requests.post(endpoint, headers=headers, json=payload, timeout=300)
    if response.status_code >= 400:
        raise RuntimeError(f'NIM call failed: HTTP {response.status_code} at {endpoint} :: {response.text[:600]}')
    data = response.json()

    def _first(v):
        if isinstance(v, list):
            return v[0] if v else None
        return v

    structure_mmcif = None
    structs = data.get('structures')
    if isinstance(structs, list) and structs:
        s0 = structs[0]
        structure_mmcif = s0.get('structure') if isinstance(s0, dict) else s0
    if not structure_mmcif:
        structure_mmcif = data.get('output_mmcif') or data.get('structure')

    confidence     = _first(data.get('confidence_scores'))
    complex_plddt  = _first(data.get('complex_plddt_scores',  data.get('complex_plddt')))
    complex_iplddt = _first(data.get('complex_iplddt_scores', data.get('complex_iplddt')))

    affinity_pic50 = affinity_pred = affinity_prob = None
    affinities = data.get('affinities')
    if isinstance(affinities, dict) and affinities:
        entry = affinities.get('L') or next(iter(affinities.values()))
        if isinstance(entry, dict):
            affinity_pic50 = _first(entry.get('affinity_pic50'))
            affinity_pred  = _first(entry.get('affinity_pred_value'))
            affinity_prob  = _first(entry.get('affinity_probability_binary'))
    if affinity_pic50 is None:
        affinity_pic50 = _first(data.get('affinity_pic50'))
    if affinity_pred is None:
        affinity_pred = _first(data.get('affinity_pred_value'))
    if affinity_prob is None:
        affinity_prob = _first(data.get('affinity_probability_binary'))

    def _f(v):
        return float(v) if v is not None else None

    rows = [{
        'PROTEIN_SEQUENCE': protein_sequence[:100],
        'LIGAND_SMILES': ligand_smiles,
        'TASK': task,
        'CONFIDENCE_SCORES': _f(confidence),
        'COMPLEX_PLDDT': _f(complex_plddt),
        'COMPLEX_IPLDDT': _f(complex_iplddt),
        'AFFINITY_PIC50': _f(affinity_pic50),
        'AFFINITY_PRED_VALUE': _f(affinity_pred),
        'AFFINITY_PROBABILITY': _f(affinity_prob),
        'STRUCTURE_MMCIF': str(structure_mmcif)[:50000] if structure_mmcif else None
    }]

    result_sp = session.create_dataframe(pd.DataFrame(rows))
    result_sp.write.mode('overwrite').save_as_table(output_table)

    score_str = f'pLDDT={complex_plddt:.3f}' if complex_plddt is not None else 'no confidence'
    affinity_str = f', pIC50={affinity_pic50:.3f}' if affinity_pic50 is not None else ''
    return f'SUCCESS: Structure predicted. {score_str}{affinity_str}. Results in {output_table}'
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_boltz2', 'Boltz-2 — Structure + Affinity',
    'Predict biomolecular structures and binding affinity using Boltz-2 NIM. Verified on SPCS L40S. Returns mmCIF + pLDDT + pIC50.',
    'structural,affinity,drug-discovery', 'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_BOLTZ2',
    '{"protein_sequence":"STRING","ligand_smiles":"STRING","task":"STRING","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_BOLTZ2(sequence, smiles, complex, output_table)'
);
