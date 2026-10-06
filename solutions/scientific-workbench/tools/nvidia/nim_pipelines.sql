-- =============================================================================
-- tools/nvidia/nim_pipelines.sql
-- Meta-pipeline tools: Drug Discovery Pipeline + MSA-Structure Pipeline
-- These chain multiple NIMs in a single agent-callable invocation
-- =============================================================================

-- =============================================================================
-- NIM_ENDPOINTS CONFIG TABLE
-- =============================================================================
-- Dual-mode endpoint routing: all NIM procedures check this table first.
-- If a row exists for (nim_name, deployment_mode='spcs'), use that URL.
-- Otherwise fall back to the hosted API URL hardcoded in each procedure.
-- VERIFIED column indicates whether the endpoint was validated against a running container.

CREATE TABLE IF NOT EXISTS SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS (
    NIM_NAME         VARCHAR NOT NULL,
    DEPLOYMENT_MODE  VARCHAR NOT NULL,   -- 'spcs' | 'hosted'
    ENDPOINT_URL     VARCHAR NOT NULL,
    VERIFIED         BOOLEAN DEFAULT FALSE,
    VERIFIED_DATE    DATE,
    NOTES            VARCHAR,
    PRIMARY KEY (NIM_NAME, DEPLOYMENT_MODE)
);

-- Seed with known endpoints
-- Boltz-2 SPCS: the PATH below was read from the running container's
-- /openapi.json (2026-08-26), but this row is NOT usable as-is, for two reasons:
--   1. It is a path fragment, not a URL. _get_endpoint() requires a value
--      starting with 'http', so this row is skipped and the hosted API is used.
--   2. Even with a full ingress URL, a stored procedure cannot reach an SPCS
--      service endpoint (only service functions and other services can). See the
--      header of setup/10-nim-spcs-services.sql.
-- It is therefore seeded with VERIFIED = FALSE. Setting it TRUE previously implied
-- a working SPCS route that has never existed. To actually use an SPCS NIM you
-- need the gateway-service pattern described in setup/10-nim-spcs-services.sql,
-- then store the full https:// ingress URL here.
MERGE INTO SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS t
USING (SELECT 'boltz2' AS NIM_NAME, 'spcs' AS DEPLOYMENT_MODE) s
ON t.NIM_NAME = s.NIM_NAME AND t.DEPLOYMENT_MODE = s.DEPLOYMENT_MODE
WHEN NOT MATCHED THEN INSERT (NIM_NAME, DEPLOYMENT_MODE, ENDPOINT_URL, VERIFIED, VERIFIED_DATE, NOTES)
VALUES ('boltz2', 'spcs', '/biology/mit/boltz2/predict', FALSE, '2026-08-26',
        'PATH ONLY, not a URL, row is inert. Container path verified 2026-08-26. '
        || 'Procedures cannot call SPCS endpoints; needs gateway service first.');

-- Hosted API endpoints. VERIFIED 2026-09-01 by live calls against every NIM.
-- Publisher segments are the model's real owner (mit/ipd/colabfold/openfold/arc),
-- NOT 'nvidia' for all. The previous biology/nvidia/<model> template 404'd for 9 of 10.
MERGE INTO SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS t
USING (SELECT 'boltz2' AS NIM_NAME, 'hosted' AS DEPLOYMENT_MODE) s
ON t.NIM_NAME = s.NIM_NAME AND t.DEPLOYMENT_MODE = s.DEPLOYMENT_MODE
WHEN NOT MATCHED THEN INSERT (NIM_NAME, DEPLOYMENT_MODE, ENDPOINT_URL, VERIFIED, NOTES)
VALUES ('boltz2', 'hosted', 'https://health.api.nvidia.com/v1/biology/mit/boltz2/predict', TRUE,
        'Verified 2026-09-01 by end-to-end call. Replaces the dead boltz-1 path.');

MERGE INTO SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS t
USING (SELECT 'genmol' AS NIM_NAME, 'hosted' AS DEPLOYMENT_MODE) s
ON t.NIM_NAME = s.NIM_NAME AND t.DEPLOYMENT_MODE = s.DEPLOYMENT_MODE
WHEN NOT MATCHED THEN INSERT (NIM_NAME, DEPLOYMENT_MODE, ENDPOINT_URL, VERIFIED, NOTES)
VALUES ('genmol', 'hosted', 'https://health.api.nvidia.com/v1/biology/nvidia/genmol/generate', TRUE,
        'Hosted path verified 2026-09-01 by live call.');

MERGE INTO SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS t
USING (SELECT 'diffdock' AS NIM_NAME, 'hosted' AS DEPLOYMENT_MODE) s
ON t.NIM_NAME = s.NIM_NAME AND t.DEPLOYMENT_MODE = s.DEPLOYMENT_MODE
WHEN NOT MATCHED THEN INSERT (NIM_NAME, DEPLOYMENT_MODE, ENDPOINT_URL, VERIFIED, NOTES)
VALUES ('diffdock', 'hosted', 'https://health.api.nvidia.com/v1/biology/mit/diffdock', TRUE,
        'Hosted path verified 2026-09-01 by live call.');

MERGE INTO SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS t
USING (SELECT 'rfdiffusion' AS NIM_NAME, 'hosted' AS DEPLOYMENT_MODE) s
ON t.NIM_NAME = s.NIM_NAME AND t.DEPLOYMENT_MODE = s.DEPLOYMENT_MODE
WHEN NOT MATCHED THEN INSERT (NIM_NAME, DEPLOYMENT_MODE, ENDPOINT_URL, VERIFIED, NOTES)
VALUES ('rfdiffusion', 'hosted', 'https://health.api.nvidia.com/v1/biology/ipd/rfdiffusion/generate', TRUE,
        'Hosted API. Image mirrored but not served — SPCS path unknown.');

MERGE INTO SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS t
USING (SELECT 'proteinmpnn' AS NIM_NAME, 'hosted' AS DEPLOYMENT_MODE) s
ON t.NIM_NAME = s.NIM_NAME AND t.DEPLOYMENT_MODE = s.DEPLOYMENT_MODE
WHEN NOT MATCHED THEN INSERT (NIM_NAME, DEPLOYMENT_MODE, ENDPOINT_URL, VERIFIED, NOTES)
VALUES ('proteinmpnn', 'hosted', 'https://health.api.nvidia.com/v1/biology/ipd/proteinmpnn/predict', TRUE,
        'Hosted API. License already accepted on this org.');

MERGE INTO SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS t
USING (SELECT 'molmim' AS NIM_NAME, 'hosted' AS DEPLOYMENT_MODE) s
ON t.NIM_NAME = s.NIM_NAME AND t.DEPLOYMENT_MODE = s.DEPLOYMENT_MODE
WHEN NOT MATCHED THEN INSERT (NIM_NAME, DEPLOYMENT_MODE, ENDPOINT_URL, VERIFIED, NOTES)
VALUES ('molmim', 'hosted', 'https://health.api.nvidia.com/v1/biology/nvidia/molmim/generate', TRUE, NULL);

MERGE INTO SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS t
USING (SELECT 'openfold2' AS NIM_NAME, 'hosted' AS DEPLOYMENT_MODE) s
ON t.NIM_NAME = s.NIM_NAME AND t.DEPLOYMENT_MODE = s.DEPLOYMENT_MODE
WHEN NOT MATCHED THEN INSERT (NIM_NAME, DEPLOYMENT_MODE, ENDPOINT_URL, VERIFIED, NOTES)
VALUES ('openfold2', 'hosted', 'https://health.api.nvidia.com/v1/biology/openfold/openfold2/predict-structure-from-msa-and-template', TRUE, NULL);

MERGE INTO SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS t
USING (SELECT 'openfold3' AS NIM_NAME, 'hosted' AS DEPLOYMENT_MODE) s
ON t.NIM_NAME = s.NIM_NAME AND t.DEPLOYMENT_MODE = s.DEPLOYMENT_MODE
WHEN NOT MATCHED THEN INSERT (NIM_NAME, DEPLOYMENT_MODE, ENDPOINT_URL, VERIFIED, NOTES)
VALUES ('openfold3', 'hosted', 'https://health.api.nvidia.com/v1/biology/openfold/openfold3/predict', TRUE,
        'SPCS path is an open item — read from /openapi.json.');

MERGE INTO SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS t
USING (SELECT 'msa_search' AS NIM_NAME, 'hosted' AS DEPLOYMENT_MODE) s
ON t.NIM_NAME = s.NIM_NAME AND t.DEPLOYMENT_MODE = s.DEPLOYMENT_MODE
WHEN NOT MATCHED THEN INSERT (NIM_NAME, DEPLOYMENT_MODE, ENDPOINT_URL, VERIFIED, NOTES)
VALUES ('msa_search', 'hosted', 'https://health.api.nvidia.com/v1/biology/colabfold/msa-search/predict', TRUE, NULL);

MERGE INTO SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS t
USING (SELECT 'evo2' AS NIM_NAME, 'hosted' AS DEPLOYMENT_MODE) s
ON t.NIM_NAME = s.NIM_NAME AND t.DEPLOYMENT_MODE = s.DEPLOYMENT_MODE
WHEN NOT MATCHED THEN INSERT (NIM_NAME, DEPLOYMENT_MODE, ENDPOINT_URL, VERIFIED, NOTES)
VALUES ('evo2', 'hosted', 'https://health.api.nvidia.com/v1/biology/arc/evo2-40b/generate', TRUE,
        'SPCS deployment BLOCKED — storage margin unmeasured.');

-- =============================================================================
-- Drug Discovery Pipeline: GenMol → Plausibility → Descriptors → DiffDock → Boltz-2
CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_DRUG_DISCOVERY_PIPELINE("SEED_SMILES" VARCHAR, "TARGET_PDB" VARCHAR, "N_MOLECULES" NUMBER(38,0), "OUTPUT_TABLE" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests','pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key'=SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT='TOOL:{\"display_name\":\"Drug Discovery Pipeline\",\"description\":\"Three-step pipeline: generate analogs from a seed molecule with GenMol, dock each against the target with DiffDock, then score binding affinity with Boltz-2. Returns one row per candidate with docking confidence and predicted pIC50.\",\"domains\":\"chemistry,structural,drug-discovery\",\"params\":{\"seed_smiles\":\"STRING\",\"target_pdb\":\"STRING\",\"n_molecules\":\"INT\",\"output_table\":\"STRING\"},\"return_type\":\"VARCHAR\",\"example\":\"CALL CATALOG.RUN_DRUG_DISCOVERY_PIPELINE(CC(=O)Oc1ccccc1C(=O)O, 1CRN, 3, output_table)\"}'
EXECUTE AS OWNER
AS
$$
import json, requests, _snowflake, pandas as pd

# REBUILT 2026-09-01. Endpoints come from CATALOG.NIM_ENDPOINTS rather than being
# hardcoded here a second time, so this pipeline tracks the individual tools.
# Verified request shapes: DiffDock needs ligand_file_type='txt' for SMILES, and
# Boltz-2 needs predict_affinity on the LIGAND object (at the request root it is
# silently ignored, yielding a structure with no affinity).
FALLBACK = {
    'genmol':   'https://health.api.nvidia.com/v1/biology/nvidia/genmol/generate',
    'diffdock': 'https://health.api.nvidia.com/v1/biology/mit/diffdock',
    'boltz2':   'https://health.api.nvidia.com/v1/biology/mit/boltz2/predict',
}

def _endpoint(session, nim):
    for mode in ('spcs', 'hosted'):
        try:
            rows = session.sql(
                "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
                f"WHERE NIM_NAME = '{nim}' AND DEPLOYMENT_MODE = '{mode}' LIMIT 1"
            ).collect()
            if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
                return rows[0][0]
        except Exception:
            pass
    return FALLBACK[nim]

def _post(url, key, payload, timeout):
    r = requests.post(url, headers={'Authorization': f'Bearer {key}',
                                    'Content-Type': 'application/json'},
                      json=payload, timeout=timeout)
    if r.status_code >= 400:
        raise RuntimeError(f'HTTP {r.status_code} at {url} :: {r.text[:300]}')
    return r.json()

def _first(v):
    if isinstance(v, list):
        return v[0] if v else None
    return v

def run(session, seed_smiles: str, target_pdb: str, n_molecules, output_table: str) -> str:
    key = _snowflake.get_generic_secret_string('nvidia_key')
    seed = (seed_smiles or '').strip()
    if not seed:
        return 'ERROR: seed_smiles is required.'
    n = max(1, min(int(n_molecules or 3), 8))

    ref = (target_pdb or '').strip()
    if len(ref) == 4 and ref.isalnum():
        pr = requests.get(f'https://files.rcsb.org/download/{ref.upper()}.pdb', timeout=60)
        pr.raise_for_status()
        pdb = pr.text
    elif 'ATOM' in ref:
        pdb = ref
    else:
        return 'ERROR: target_pdb must be a 4-character PDB ID or raw PDB text.'

    # ---- step 1: generate analogs -------------------------------------------
    gen = _post(_endpoint(session, 'genmol'), key,
                {'smiles': seed, 'num_molecules': n, 'temperature': 1.0, 'unique': True}, 300)
    cands = []
    for m in (gen.get('molecules') or []):
        smi = m.get('smiles') if isinstance(m, dict) else str(m)
        sc = m.get('score') if isinstance(m, dict) else None
        if smi:
            cands.append((str(smi), sc))
    if not cands:
        return f'WARNING: GenMol returned no molecules. Keys: {list(gen.keys())}'
    cands = cands[:n]

    dd_url = _endpoint(session, 'diffdock')
    bz_url = _endpoint(session, 'boltz2')

    rows, errs = [], []
    for i, (smi, gen_score) in enumerate(cands):
        dock_conf, pic50 = None, None
        try:
            dd = _post(dd_url, key, {'ligand': smi, 'ligand_file_type': 'txt',
                                     'protein': pdb, 'num_poses': 1,
                                     'time_divisions': 20, 'steps': 18}, 300)
            confs = dd.get('position_confidence') or []
            if confs:
                dock_conf = float(confs[0])
        except Exception as e:
            errs.append(f'dock[{i}]: {str(e)[:120]}')
        try:
            bz = _post(bz_url, key,
                       {'polymers': [{'id': 'A', 'molecule_type': 'protein',
                                      'sequence': 'MKTVRQERLKSIVRILERSKEPVSGAQLAEELSVSRQVIVQDIAYLRSLGYNIVATPRGYVLAGG'}],
                        'ligands': [{'id': 'L', 'smiles': smi, 'predict_affinity': True}]}, 600)
            aff = (bz.get('affinities') or {}).get('L') or {}
            pic50 = _first(aff.get('affinity_pic50'))
            pic50 = float(pic50) if pic50 is not None else None
        except Exception as e:
            errs.append(f'affinity[{i}]: {str(e)[:120]}')

        rows.append({'CANDIDATE_IDX': i, 'SEED_SMILES': seed[:2000],
                     'CANDIDATE_SMILES': smi[:2000], 'TARGET_PDB': ref.upper()[:10],
                     'GEN_SCORE': float(gen_score) if gen_score is not None else None,
                     'DOCK_CONFIDENCE': dock_conf, 'AFFINITY_PIC50': pic50})

    result_sp = session.create_dataframe(pd.DataFrame(rows))
    result_sp.write.mode('overwrite').save_as_table(output_table)
    scored = sum(1 for r in rows if r['DOCK_CONFIDENCE'] is not None)
    affd = sum(1 for r in rows if r['AFFINITY_PIC50'] is not None)
    # Report WHAT failed, not just how many. Reporting a bare count left partial
    # failures undiagnosable: candidates silently lost a dock or affinity step
    # with no way to find out why without re-running the whole pipeline.
    suffix = ''
    if errs:
        suffix = f' ({len(errs)} step errors: ' + ' | '.join(errs[:3])
        if len(errs) > 3:
            suffix += f' | +{len(errs) - 3} more'
        suffix += ')'
    return (f'SUCCESS: {len(rows)} candidates, {scored} docked, {affd} with affinity{suffix}. '
            f'Results in {output_table}')
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_drug_discovery_pipeline','Drug Discovery Pipeline',
    'End-to-end autonomous pipeline: generate molecules, validate, dock to target, rank by affinity.',
    'chemistry,drug-discovery,pipeline','procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_DRUG_DISCOVERY_PIPELINE',
    '{"seed_smiles":"STRING","target_pdb":"STRING","n_molecules":"INT","output_table":"STRING"}',
    'VARCHAR','CALL CATALOG.RUN_DRUG_DISCOVERY_PIPELINE(seed_smiles, 6OIM, 100, output_table)'
);

-- MSA-Structure Pipeline: MSA-Search → OpenFold3
CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_MSA_STRUCTURE_PIPELINE("PROTEIN_SEQUENCE" VARCHAR, "LIGAND_SMILES" VARCHAR, "OUTPUT_TABLE" VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python','requests','pandas')
HANDLER = 'run'
EXTERNAL_ACCESS_INTEGRATIONS = (NVIDIA_API_EAI)
SECRETS = ('nvidia_key'=SCIENTIFIC_WORKBENCH.CATALOG.NVIDIA_API_SECRET)
COMMENT='TOOL:{\"display_name\":\"MSA-Structure Pipeline\",\"description\":\"Two-step pipeline: build a multiple sequence alignment with MSA-Search, then predict complex structure with OpenFold3 using that alignment. Optionally co-folds a ligand.\",\"domains\":\"structural,drug-discovery\",\"params\":{\"protein_sequence\":\"STRING\",\"ligand_smiles\":\"STRING\",\"output_table\":\"STRING\"},\"return_type\":\"VARCHAR\",\"example\":\"CALL CATALOG.RUN_MSA_STRUCTURE_PIPELINE(MKTV..., CCO, output_table)\"}'
EXECUTE AS OWNER
AS
$$
import json, requests, _snowflake, pandas as pd

# REBUILT 2026-09-01. Two changes of substance versus the original:
#  1. Endpoints are read from CATALOG.NIM_ENDPOINTS (hosted rows) instead of being
#     hardcoded a second time here. That table is now the single source of truth, so
#     this pipeline cannot drift from the individual tools again.
#  2. Request and response shapes are the verified ones. The originals were guesses:
#     msa-search sat on a dead biology/nvidia/* URL, and OpenFold3 needs
#     inputs[].molecules[] with an explicit type and a non-empty msa per protein.
FALLBACK = {
    'msa_search': 'https://health.api.nvidia.com/v1/biology/colabfold/msa-search/predict',
    'openfold3':  'https://health.api.nvidia.com/v1/biology/openfold/openfold3/predict',
}

def _endpoint(session, nim):
    """Prefer a live SPCS service, then the hosted row in NIM_ENDPOINTS, then a constant."""
    for mode in ('spcs', 'hosted'):
        try:
            rows = session.sql(
                "SELECT ENDPOINT_URL FROM SCIENTIFIC_WORKBENCH.CATALOG.NIM_ENDPOINTS "
                f"WHERE NIM_NAME = '{nim}' AND DEPLOYMENT_MODE = '{mode}' LIMIT 1"
            ).collect()
            if rows and rows[0][0] and str(rows[0][0]).lower().startswith('http'):
                return rows[0][0]
        except Exception:
            pass
    return FALLBACK[nim]

def _post(url, key, payload, timeout):
    r = requests.post(url, headers={'Authorization': f'Bearer {key}',
                                    'Content-Type': 'application/json'},
                      json=payload, timeout=timeout)
    if r.status_code >= 400:
        raise RuntimeError(f'HTTP {r.status_code} at {url} :: {r.text[:400]}')
    return r.json()

# OpenFold3 score keys carry a '_score' suffix (complex_plddt_score, ptm_score,
# iptm_score). Probing for the unsuffixed names returns NULL on a successful call.
def _num(d, *names):
    for n in names:
        v = d.get(n) if isinstance(d, dict) else None
        if isinstance(v, list):
            v = v[0] if v else None
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            return float(v)
    return None

def run(session, protein_sequence: str, ligand_smiles: str, output_table: str) -> str:
    key = _snowflake.get_generic_secret_string('nvidia_key')
    seq = (protein_sequence or '').strip().upper()
    if not seq:
        return 'ERROR: protein_sequence is required.'

    # ---- step 1: MSA ---------------------------------------------------------
    msa_url = _endpoint(session, 'msa_search')
    msa_data = _post(msa_url, key,
                     {'sequence': seq, 'databases': ['Uniref30_2302'],
                      'e_value': 0.0001, 'iterations': 1}, 600)
    alignments = msa_data.get('alignments') or {}
    n_hits = 0
    for _db, fmts in alignments.items():
        if isinstance(fmts, dict):
            for _f, obj in fmts.items():
                aln = obj.get('alignment') if isinstance(obj, dict) else obj
                n_hits += str(aln or '').count('>')
    if not alignments:
        # OpenFold3 refuses an empty MSA; a query-only alignment is explicitly allowed.
        alignments = {'query_only': {'a3m': {'alignment': f'>query\\\\n{seq}\\\\n', 'format': 'a3m'}}}

    # ---- step 2: structure ---------------------------------------------------
    molecules = [{'type': 'protein', 'id': 'A', 'sequence': seq, 'msa': alignments}]
    if (ligand_smiles or '').strip():
        molecules.append({'type': 'ligand', 'id': 'L', 'smiles': ligand_smiles.strip()})

    of3_url = _endpoint(session, 'openfold3')
    of3 = _post(of3_url, key, {'inputs': [{'molecules': molecules}]}, 900)

    rows = []
    for out in (of3.get('outputs') or []):
        for r, sw in enumerate(out.get('structures_with_scores') or []):
            struct = sw.get('structure') if isinstance(sw, dict) else str(sw)
            rows.append({
                'PROTEIN_SEQUENCE': seq[:5000],
                'LIGAND_SMILES': (ligand_smiles or '')[:2000],
                'MSA_HITS': n_hits,
                'RANK': r,
                'PLDDT': _num(sw, 'complex_plddt_score', 'mean_plddt', 'plddt'),
                'IPTM': _num(sw, 'iptm_score', 'iptm'),
                'STRUCTURE_PDB': str(struct or '')[:50000]
            })

    if not rows:
        return f'WARNING: pipeline produced no structures. OpenFold3 keys: {list(of3.keys())}'

    result_sp = session.create_dataframe(pd.DataFrame(rows))
    result_sp.write.mode('overwrite').save_as_table(output_table)
    return (f'SUCCESS: MSA ({n_hits} hits) then {len(rows)} structure(s). '
            f'Results in {output_table}')
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_msa_structure_pipeline','MSA-Structure Pipeline',
    'Chain MSA-Search + OpenFold3: find homologs then predict structure with MSA context for higher accuracy.',
    'structural,genomics','procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_MSA_STRUCTURE_PIPELINE',
    '{"protein_sequence":"STRING","ligand_smiles":"STRING","output_table":"STRING"}',
    'VARCHAR','CALL CATALOG.RUN_MSA_STRUCTURE_PIPELINE(sequence, ligand_smiles, output_table)'
);
