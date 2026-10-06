-- =============================================================================
-- tools/nvidia/nim_remaining.sql
-- MolMIM, OpenFold2, OpenFold3, MSA-Search, Evo2
-- =============================================================================
-- All SPCS endpoint paths UNKNOWN — read from container /openapi.json after deployment.
-- All procedures use dual-mode: check NIM_ENDPOINTS table for SPCS URL, fall back to hosted API.
-- All SPCS service specs require /dev/shm memory volume (see 10-nim-spcs-services.sql).
--
-- SPECIAL CASES:
--   MSA-Search: SPCS deployment requires block volume for reference databases (up to 1.2 TB)
--   Evo2: SPCS deployment BLOCKED — runtime footprint vs 93.13 GiB cap is unmeasured
-- =============================================================================

-- =============================================================================
-- MolMIM
-- =============================================================================
CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_MOLMIM("SEED_SMILES" VARCHAR, "OPTIMIZE_FOR" VARCHAR, "N_STEPS" NUMBER(38,0), "N_SAMPLES" NUMBER(38,0), "OUTPUT_TABLE" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests','pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key'=SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT='TOOL:{\"display_name\":\"MolMIM — Molecule Optimization\",\"description\":\"Optimize a seed molecule toward a target property (QED or penalized logP) using MolMIM NIM with CMA-ES guided latent search. Returns optimized analogs with scores.\",\"domains\":\"chemistry,drug-discovery\",\"params\":{\"seed_smiles\":\"STRING\",\"optimize_for\":\"STRING\",\"n_steps\":\"INT\",\"n_samples\":\"INT\",\"output_table\":\"STRING\"},\"return_type\":\"VARCHAR\",\"example\":\"CALL CATALOG.RUN_MOLMIM(CC(=O)Oc1ccccc1C(=O)O, qed, 10, 5, output_table)\"}'
EXECUTE AS OWNER
AS
$$
import json, requests, _snowflake, pandas as pd

# VERIFIED 2026-09-01 against the live hosted API.
#   endpoint : /v1/biology/nvidia/molmim/generate
#              The '/generate' suffix is required; the bare model path 404s.
#   request  : smi (NOT 'smiles'), algorithm, num_molecules, property_name,
#              minimize, min_similarity, particles, iterations.
#              Sending an unexpected body shape produces a confusing internal
#              C++ converter error rather than a clean validation message.
#   response : molecules, score_type. 'molecules' may be a JSON string.
HOSTED_ENDPOINT = 'https://health.api.nvidia.com/v1/biology/nvidia/molmim/generate'
PROPERTY_MAP = {'qed': 'QED', 'logp': 'plogP', 'plogp': 'plogP', 'sa_score': 'QED', 'custom': 'QED'}

def _get_endpoint(session):
    try:
        rows = session.sql(
            "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
            "WHERE NIM_NAME = 'molmim' AND DEPLOYMENT_MODE = 'spcs' LIMIT 1"
        ).collect()
        if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
            return rows[0][0]
    except Exception:
        pass
    return HOSTED_ENDPOINT

def run(session, seed_smiles: str, optimize_for: str, n_steps: int, n_samples: int, output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    endpoint = _get_endpoint(session)

    seed = (seed_smiles or '').strip()
    if not seed:
        return 'ERROR: seed_smiles is required.'

    prop = PROPERTY_MAP.get((optimize_for or 'qed').strip().lower(), 'QED')
    payload = {
        'smi': seed,
        'algorithm': 'CMA-ES',
        'num_molecules': max(1, min(int(n_samples or 5), 50)),
        'property_name': prop,
        'minimize': False,
        'min_similarity': 0.7,
        'particles': max(8, min(int(n_samples or 5) * 2, 60)),
        'iterations': max(1, min(int(n_steps or 10), 100))
    }

    response = requests.post(
        endpoint,
        headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
        json=payload, timeout=600
    )
    if response.status_code >= 400:
        raise RuntimeError(f'NIM call failed: HTTP {response.status_code} at {endpoint} :: {response.text[:500]}')
    data = response.json()

    mols = data.get('molecules', data.get('optimized_molecules', []))
    if isinstance(mols, str):
        try:
            mols = json.loads(mols)
        except Exception:
            mols = []

    rows = []
    for i, m in enumerate(mols or []):
        if isinstance(m, dict):
            smi = m.get('smiles') or m.get('sample') or m.get('smi') or ''
            sc = m.get('score', m.get(prop))
        else:
            smi, sc = str(m), None
        try:
            sc = float(sc) if sc is not None else None
        except (TypeError, ValueError):
            sc = None
        if smi:
            rows.append({'SMILES': str(smi)[:2000], 'SCORE': sc, 'SEED_SMILES': seed[:2000],
                         'OPTIMIZE_FOR': prop, 'SAMPLE_IDX': i,
                         'SCORE_TYPE': str(data.get('score_type') or '')[:60]})

    if not rows:
        return f'WARNING: No molecules returned. Response keys: {list(data.keys())}'

    result_sp = session.create_dataframe(pd.DataFrame(rows))
    result_sp.write.mode('overwrite').save_as_table(output_table)
    return f'SUCCESS: Generated {len(rows)} optimized molecules for {prop}. Results in {output_table}'
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_molmim','MolMIM — Molecule Optimization',
    'Optimize molecules in latent space toward target properties (QED, LogP) using MolMIM NIM.',
    'chemistry,drug-discovery,optimization','procedure','SCIENTIFIC_WORKBENCH.CATALOG.RUN_MOLMIM',
    '{"seed_smiles":"STRING","optimize_for":"STRING","n_steps":"INT","n_samples":"INT","output_table":"STRING"}',
    'VARCHAR','CALL CATALOG.RUN_MOLMIM(seed_smiles, qed, 100, 50, output_table)'
);

-- =============================================================================
-- OpenFold2
-- =============================================================================
CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_OPENFOLD2("PROTEIN_SEQUENCE" VARCHAR, "OUTPUT_TABLE" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests','pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key'=SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT='TOOL:{\"display_name\":\"OpenFold2 — Monomer Structure\",\"description\":\"Predict the 3D structure of a single protein chain using OpenFold2 NIM. Returns ranked structures with confidence metrics.\",\"domains\":\"structural\",\"params\":{\"protein_sequence\":\"STRING\",\"output_table\":\"STRING\"},\"return_type\":\"VARCHAR\",\"example\":\"CALL CATALOG.RUN_OPENFOLD2(MKTVRQERLK..., output_table)\"}'
EXECUTE AS OWNER
AS
$$
import json, requests, _snowflake, pandas as pd

# VERIFIED 2026-09-01 against the live hosted API.
#   endpoint : /v1/biology/openfold/openfold2/predict-structure-from-msa-and-template
#   request  : sequence, selected_models[]
#   response : structures_in_ranked_order[], input_id, metrics,
#              of2_nim_handled_error_message
#
# TRAP: of2_nim_handled_error_message is a SENTINEL, not an optional field. On a
# fully successful call it is the literal string 'no-handled-error'. Treating any
# non-empty value as a failure makes every successful prediction look like an error.
HOSTED_ENDPOINT = 'https://health.api.nvidia.com/v1/biology/openfold/openfold2/predict-structure-from-msa-and-template'
NO_ERROR_SENTINELS = ('', 'none', 'null', 'no-handled-error')

def _get_endpoint(session):
    try:
        rows = session.sql(
            "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
            "WHERE NIM_NAME = 'openfold2' AND DEPLOYMENT_MODE = 'spcs' LIMIT 1"
        ).collect()
        if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
            return rows[0][0]
    except Exception:
        pass
    return HOSTED_ENDPOINT

def _num(d, *names):
    for n in names:
        v = d.get(n) if isinstance(d, dict) else None
        if isinstance(v, list):
            v = v[0] if v else None
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            return float(v)
    return None

def run(session, protein_sequence: str, output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    endpoint = _get_endpoint(session)

    seq = (protein_sequence or '').strip().upper()
    if not seq:
        return 'ERROR: protein_sequence is required.'

    response = requests.post(
        endpoint,
        headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
        json={'sequence': seq, 'selected_models': [1]}, timeout=900
    )
    # A 5xx here is an NVIDIA-side fault, not a bad request from us. Raising a
    # RuntimeError surfaced a raw Python traceback to the agent and the UI, which
    # read like a workbench bug. Return a classified message instead.
    #
    # OBSERVED 2026-09-08: this endpoint returned HTTP 500
    #   "CUDA error: an illegal memory access was encountered"
    # for every request, at 21, 76 and 129 residues, across six payload shapes.
    # The fault is in NVIDIA's hosted GPU, so there is nothing to fix here.
    # OpenFold3 (run_openfold3) was working and is the recommended alternative.
    if response.status_code >= 500:
        return (f'UPSTREAM_ERROR: OpenFold2 hosted NIM returned HTTP {response.status_code}. '
                f'This is a failure inside NVIDIA\'s service, not in the workbench. '
                f'Use run_openfold3 instead, or retry later. '
                f'Detail: {response.text[:300]}')
    if response.status_code >= 400:
        return (f'REQUEST_ERROR: OpenFold2 rejected the request with HTTP {response.status_code}. '
                f'Detail: {response.text[:300]}')
    data = response.json()

    err = str(data.get('of2_nim_handled_error_message') or '').strip()
    if err.lower() not in NO_ERROR_SENTINELS:
        return f'WARNING: OpenFold2 reported: {err[:400]}'

    structs = data.get('structures_in_ranked_order') or []
    metrics = data.get('metrics') or {}

    rows = []
    for i, s in enumerate(structs):
        if isinstance(s, dict):
            struct_text = s.get('structure') or s.get('pdb') or s.get('cif') or ''
            plddt = _num(s, 'mean_plddt', 'plddt', 'confidence')
            ptm = _num(s, 'ptm', 'ptm_score')
        else:
            struct_text, plddt, ptm = str(s), None, None
        if plddt is None:
            plddt = _num(metrics, 'mean_plddt', 'plddt')
        if ptm is None:
            ptm = _num(metrics, 'ptm', 'ptm_score')
        rows.append({'SEQUENCE': seq[:5000], 'RANK': i, 'PLDDT': plddt, 'PTM': ptm,
                     'STRUCTURE_PDB': str(struct_text)[:50000]})

    if not rows:
        return f'WARNING: No structures returned. Response keys: {list(data.keys())}'

    result_sp = session.create_dataframe(pd.DataFrame(rows))
    result_sp.write.mode('overwrite').save_as_table(output_table)
    top = rows[0]
    score = f", top pLDDT={top['PLDDT']:.3f}" if top['PLDDT'] is not None else ''
    return f'SUCCESS: Predicted {len(rows)} structure(s){score}. Results in {output_table}'
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_openfold2','OpenFold2 — Monomer Structure',
    'Predict single-chain protein structure using OpenFold2 NIM. Returns PDB structure and pLDDT.',
    'structural,protein','procedure','SCIENTIFIC_WORKBENCH.CATALOG.RUN_OPENFOLD2',
    '{"protein_sequence":"STRING","output_table":"STRING"}','VARCHAR',
    'CALL CATALOG.RUN_OPENFOLD2(sequence, output_table)'
);

-- =============================================================================
-- OpenFold3
-- =============================================================================
CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_OPENFOLD3("SEQUENCES" VARIANT, "OUTPUT_TABLE" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests','pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key'=SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT='TOOL:{\"display_name\":\"OpenFold3 — Complex Structure\",\"description\":\"Predict the 3D structure of a biomolecular complex (proteins, DNA, RNA, ligands) using OpenFold3 NIM. Each protein chain requires an MSA, generated automatically as a query-only alignment if none is supplied. Returns structure plus complex pLDDT, pTM and ipTM.\",\"domains\":\"structural,drug-discovery\",\"params\":{\"sequences\":\"VARIANT\",\"output_table\":\"STRING\"},\"return_type\":\"VARCHAR\",\"example\":\"CALL CATALOG.RUN_OPENFOLD3(PARSE_JSON(...), output_table)\"}'
EXECUTE AS OWNER
AS
$$
import json, requests, _snowflake, pandas as pd

# VERIFIED 2026-09-01 against the live hosted API.
#   endpoint : /v1/biology/openfold/openfold3/predict   (publisher 'openfold')
#   request  : inputs[].molecules[] each with an explicit 'type'; every protein
#              MUST carry a non-empty 'msa'. A query-only a3m is explicitly allowed
#              and is synthesised here so the tool works without an MSA-Search call.
#   response : outputs[].structures_with_scores[] with keys
#              structure, format, name, source, confidence_score,
#              complex_plddt_score, complex_pde_score, ptm_score, iptm_score.
#              NOTE the '_score' suffix: probing for 'mean_plddt'/'plddt'/'ptm'
#              silently yielded NULL confidence on an otherwise successful call.
HOSTED_ENDPOINT = 'https://health.api.nvidia.com/v1/biology/openfold/openfold3/predict'

def _get_endpoint(session):
    for mode in ('spcs', 'hosted'):
        try:
            rows = session.sql(
                "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
                f"WHERE NIM_NAME = 'openfold3' AND DEPLOYMENT_MODE = '{mode}' LIMIT 1"
            ).collect()
            if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
                return rows[0][0]
        except Exception:
            pass
    return HOSTED_ENDPOINT

def _query_only_msa(seq):
    return {'query_only': {'a3m': {'alignment': f'>query\\n{seq}\\n', 'format': 'a3m'}}}

def _num(d, *names):
    for n in names:
        v = d.get(n) if isinstance(d, dict) else None
        if isinstance(v, list):
            v = v[0] if v else None
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            return float(v)
    return None

def run(session, sequences, output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    endpoint = _get_endpoint(session)

    spec = sequences
    if isinstance(spec, str):
        spec = json.loads(spec)
    if isinstance(spec, dict):
        spec = [spec]
    if not spec:
        return 'ERROR: sequences must be a non-empty JSON array.'

    molecules = []
    for i, item in enumerate(spec):
        if not isinstance(item, dict):
            continue
        mtype = str(item.get('type') or item.get('molecule_type') or 'protein').lower()
        chain_id = str(item.get('id') or chr(ord('A') + (i % 26)))
        if mtype == 'ligand':
            smi = item.get('smiles') or item.get('smi')
            if smi:
                molecules.append({'type': 'ligand', 'id': chain_id, 'smiles': str(smi)})
            continue
        seq = str(item.get('sequence') or '').strip().upper()
        if not seq:
            continue
        mol = {'type': mtype, 'id': chain_id, 'sequence': seq}
        if mtype == 'protein':
            mol['msa'] = item.get('msa') or _query_only_msa(seq)
        molecules.append(mol)

    if not molecules:
        return 'ERROR: no usable molecules parsed from the sequences argument.'

    response = requests.post(
        endpoint,
        headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
        json={'inputs': [{'molecules': molecules}]}, timeout=900
    )
    if response.status_code >= 400:
        raise RuntimeError(f'NIM call failed: HTTP {response.status_code} at {endpoint} :: {response.text[:600]}')
    data = response.json()

    rows = []
    for out in (data.get('outputs') or []):
        for r, sw in enumerate(out.get('structures_with_scores') or []):
            struct = sw.get('structure') if isinstance(sw, dict) else str(sw)
            rows.append({
                'INPUT_ID': str(out.get('input_id') or '')[:100],
                'RANK': r,
                'PLDDT': _num(sw, 'complex_plddt_score', 'mean_plddt', 'plddt'),
                'PTM': _num(sw, 'ptm_score', 'ptm'),
                'IPTM': _num(sw, 'iptm_score', 'iptm'),
                'CONFIDENCE': _num(sw, 'confidence_score'),
                'N_MOLECULES': len(molecules),
                'STRUCTURE_PDB': str(struct or '')[:50000]
            })

    if not rows:
        return f'WARNING: No structures returned. Response keys: {list(data.keys())}'

    result_sp = session.create_dataframe(pd.DataFrame(rows))
    result_sp.write.mode('overwrite').save_as_table(output_table)
    top = rows[0]
    score = f", complex pLDDT={top['PLDDT']:.2f}" if top['PLDDT'] is not None else ''
    return f'SUCCESS: Predicted {len(rows)} structure(s) for {len(molecules)} molecule(s){score}. Results in {output_table}'
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_openfold3','OpenFold3 — Complex Structure',
    'Predict multi-chain complex structure using OpenFold3 NIM.',
    'structural,protein','procedure','SCIENTIFIC_WORKBENCH.CATALOG.RUN_OPENFOLD3',
    '{"sequences":"VARIANT","output_table":"STRING"}','VARCHAR',
    'CALL CATALOG.RUN_OPENFOLD3(PARSE_JSON(json_array), output_table)'
);

-- =============================================================================
-- MSA-Search
-- =============================================================================
CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_MSA_SEARCH("PROTEIN_SEQUENCE" VARCHAR, "OUTPUT_TABLE" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests','pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key'=SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT='TOOL:{\"display_name\":\"MSA-Search — Sequence Alignment\",\"description\":\"Build a multiple sequence alignment for a protein sequence using ColabFold MSA-Search NIM. Produces the a3m alignment that OpenFold3 requires as input.\",\"domains\":\"structural,genomics\",\"params\":{\"protein_sequence\":\"STRING\",\"output_table\":\"STRING\"},\"return_type\":\"VARCHAR\",\"example\":\"CALL CATALOG.RUN_MSA_SEARCH(MKTVRQERLK..., output_table)\"}'
EXECUTE AS OWNER
AS
$$
import json, requests, _snowflake, pandas as pd

# VERIFIED 2026-09-01 against the live hosted API.
#   endpoint : /v1/biology/colabfold/msa-search/predict  (publisher is colabfold)
#   request  : sequence, databases[], e_value, iterations
#   response : alignments.<db>.a3m.alignment  (an a3m string), templates, metrics
#              NOT a flat 'msa' key. That nested object is exactly the shape
#              OpenFold3 wants for its per-molecule 'msa' field, so RAW_ALIGNMENTS
#              below can be handed straight to RUN_OPENFOLD3.
# NOTE: a stored procedure cannot CREATE TEMPORARY TABLE ("Unsupported statement
# type"), so the raw object is carried in a column instead of a scratch table.
HOSTED_ENDPOINT = 'https://health.api.nvidia.com/v1/biology/colabfold/msa-search/predict'
DEFAULT_DBS = ['Uniref30_2302']

def _get_endpoint(session):
    try:
        rows = session.sql(
            "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
            "WHERE NIM_NAME = 'msa_search' AND DEPLOYMENT_MODE = 'spcs' LIMIT 1"
        ).collect()
        if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
            return rows[0][0]
    except Exception:
        pass
    return HOSTED_ENDPOINT

def run(session, protein_sequence: str, output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    endpoint = _get_endpoint(session)

    seq = (protein_sequence or '').strip().upper()
    if not seq:
        return 'ERROR: protein_sequence is required.'

    payload = {'sequence': seq, 'databases': DEFAULT_DBS, 'e_value': 0.0001, 'iterations': 1}

    response = requests.post(
        endpoint,
        headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
        json=payload, timeout=600
    )
    if response.status_code >= 400:
        raise RuntimeError(f'NIM call failed: HTTP {response.status_code} at {endpoint} :: {response.text[:500]}')
    data = response.json()

    alignments = data.get('alignments') or {}
    raw_json = json.dumps(alignments)

    rows = []
    for db, formats in alignments.items():
        if not isinstance(formats, dict):
            continue
        for fmt_name, obj in formats.items():
            aln = obj.get('alignment') if isinstance(obj, dict) else obj
            aln = str(aln or '')
            rows.append({
                'QUERY_SEQUENCE': seq[:5000],
                'DATABASE': str(db)[:100],
                'FORMAT': str(fmt_name)[:20],
                'N_SEQUENCES': aln.count('>'),
                'ALIGNMENT': aln[:100000],
                'RAW_ALIGNMENTS': raw_json[:150000]
            })

    if not rows:
        return f'WARNING: No alignments returned. Response keys: {list(data.keys())}'

    result_sp = session.create_dataframe(pd.DataFrame(rows))
    result_sp.write.mode('overwrite').save_as_table(output_table)
    total = sum(r['N_SEQUENCES'] for r in rows)
    return f'SUCCESS: Built MSA with {total} sequences across {len(rows)} database/format pair(s). Results in {output_table}'
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_msa_search','MSA-Search — Sequence Alignment',
    'Generate MSA for a protein using ColabFold MSA-Search NIM. Feed to structure prediction for higher accuracy.',
    'genomics,structural,protein','procedure','SCIENTIFIC_WORKBENCH.CATALOG.RUN_MSA_SEARCH',
    '{"protein_sequence":"STRING","output_table":"STRING"}','VARCHAR',
    'CALL CATALOG.RUN_MSA_SEARCH(sequence, output_table)'
);

-- =============================================================================
-- Evo2
-- =============================================================================
CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_EVO2("PROMPT_SEQUENCE" VARCHAR, "N_TOKENS" NUMBER(38,0), "OUTPUT_TABLE" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests','pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key'=SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT='TOOL:{\"display_name\":\"Evo2 — DNA/RNA Generation\",\"description\":\"Generate or extend nucleotide sequences using the Evo 2 genomic foundation model. Takes a DNA/RNA prompt and autoregressively generates new tokens.\",\"domains\":\"genomics\",\"params\":{\"prompt_sequence\":\"STRING\",\"n_tokens\":\"INT\",\"output_table\":\"STRING\"},\"return_type\":\"VARCHAR\",\"example\":\"CALL CATALOG.RUN_EVO2(ACGTACGTACGT, 64, output_table)\"}'
EXECUTE AS OWNER
AS
$$
import json, requests, _snowflake, pandas as pd

# VERIFIED 2026-09-01 against the live hosted API.
#   endpoint : /v1/biology/arc/evo2-40b/generate
#              Publisher is 'arc' and the model id carries the parameter count
#              ('evo2-40b'); plain 'evo2' 404s.
#   request  : sequence (REQUIRED), num_tokens
#   response : sequence, logits, sampled_probs, elapsed_ms, elapsed_ms_per_token
HOSTED_ENDPOINT = 'https://health.api.nvidia.com/v1/biology/arc/evo2-40b/generate'

def _get_endpoint(session):
    try:
        rows = session.sql(
            "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
            "WHERE NIM_NAME = 'evo2' AND DEPLOYMENT_MODE = 'spcs' LIMIT 1"
        ).collect()
        if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
            return rows[0][0]
    except Exception:
        pass
    return HOSTED_ENDPOINT

def run(session, prompt_sequence: str, n_tokens: int, output_table: str) -> str:
    api_key = _snowflake.get_generic_secret_string('nvidia_key')
    endpoint = _get_endpoint(session)

    prompt = (prompt_sequence or '').strip().upper()
    if not prompt:
        return 'ERROR: prompt_sequence is required.'

    payload = {'sequence': prompt, 'num_tokens': max(1, min(int(n_tokens or 32), 1024))}

    response = requests.post(
        endpoint,
        headers={'Authorization': f'Bearer {api_key}', 'Content-Type': 'application/json'},
        json=payload, timeout=300
    )
    if response.status_code >= 400:
        raise RuntimeError(f'NIM call failed: HTTP {response.status_code} at {endpoint} :: {response.text[:500]}')
    data = response.json()

    generated = data.get('sequence') or data.get('generated_sequence') or ''
    if isinstance(generated, list):
        generated = generated[0] if generated else ''

    rows = [{
        'PROMPT': prompt[:5000],
        'GENERATED_SEQUENCE': str(generated)[:15000],
        'TOTAL_LENGTH': len(str(generated)),
        'N_TOKENS_REQUESTED': int(payload['num_tokens']),
        'ELAPSED_MS': float(data.get('elapsed_ms') or 0.0)
    }]

    if not generated:
        return f'WARNING: No sequence returned. Response keys: {list(data.keys())}'

    result_sp = session.create_dataframe(pd.DataFrame(rows))
    result_sp.write.mode('overwrite').save_as_table(output_table)
    return f'SUCCESS: Generated {len(str(generated))} nucleotides. Results in {output_table}'
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_evo2','Evo2 — DNA/RNA Generation',
    'Generate genomic sequences from a prompt using Evo2 NIM.',
    'genomics,generative','procedure','SCIENTIFIC_WORKBENCH.CATALOG.RUN_EVO2',
    '{"prompt_sequence":"STRING","n_tokens":"INT","output_table":"STRING"}','VARCHAR',
    'CALL CATALOG.RUN_EVO2(prompt_dna, 500, output_table)'
);
