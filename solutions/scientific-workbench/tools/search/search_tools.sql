-- =============================================================================
-- tools/search/search_tools.sql
-- Clinical trials search (CKE-backed) + asset catalog search (local Cortex Search).
--
-- FIXED 2026-09-08: both procedures called their service as
--     FROM TABLE(<service>!SEARCH(QUERY => ..., COLUMNS => ..., MAX_RESULTS => ...))
-- That method syntax is not available on this account and failed with
--     "Unknown user-defined table function ...!SEARCH"
-- Both procedures caught the error and returned a JSON {"status":"error"} body
-- from an otherwise SUCCESSFUL call, so they appeared healthy to any check that
-- only asked whether the CALL threw. search_asset_catalog was broken this way
-- even though its ASSET_SEARCH service exists and is ACTIVE.
-- Verified working entry point: SNOWFLAKE.CORTEX.SEARCH_PREVIEW(service, request).
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.SEARCH_CLINICAL_TRIALS(
    query       VARCHAR,
    max_results INT
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
COMMENT = 'TOOL:{"display_name":"Clinical Trials Search","description":"Semantic search over ClinicalTrials.gov trials via a CKE Marketplace subscription.","domains":"clinical,trials","params":{"query":"STRING","max_results":"INT"},"return_type":"VARCHAR","example":"CALL CATALOG.SEARCH_CLINICAL_TRIALS(query, 5)"}'
AS
$$
import json

SERVICE = 'SCIENTIFIC_WORKBENCH.CATALOG.CLINICAL_TRIALS_CKE_SEARCH'
COLUMNS = ['NCT_ID', 'TITLE', 'PHASE', 'STATUS', 'CONDITIONS', 'INTERVENTIONS', 'SPONSOR']

def _search(session, service, request):
    rows = session.sql(
        "SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(?, ?) AS R",
        params=[service, request],
    ).collect()
    return json.loads(rows[0][0]) if rows and rows[0][0] else {}

def run(session, query: str, max_results: int) -> str:
    if not query or not str(query).strip():
        return json.dumps({'status': 'error', 'message': 'query is required'})

    limit = max(1, min(int(max_results or 5), 100))
    attempts = [
        json.dumps({'query': str(query), 'columns': COLUMNS, 'limit': limit}),
        json.dumps({'query': str(query), 'limit': limit}),
    ]

    last = ''
    for request in attempts:
        try:
            payload = _search(session, SERVICE, request)
        except Exception as e:
            last = str(e)
            low = last.lower()
            if 'does not exist' in low or 'not authorized' in low or 'unknown' in low:
                return json.dumps({
                    'status': 'unavailable',
                    'service': SERVICE,
                    'message': (
                        f'Cortex Search service {SERVICE} is not available in this '
                        'account. Clinical trials search requires the '
                        'ClinicalTrials.gov Cortex Knowledge Extension from Snowflake '
                        'Marketplace. Subscribe to it, then create the search service '
                        'under that name.'
                    ),
                    'detail': last[:300],
                })
            continue

        results = payload.get('results') or []
        rows = [{k: v for k, v in r.items() if k != '@scores'} for r in results if isinstance(r, dict)]
        if rows or 'results' in payload:
            return json.dumps({'status': 'success', 'count': len(rows), 'results': rows})

    return json.dumps({'status': 'error', 'message': (last or 'no results returned')[:500]})
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'search_clinical_trials', 'Clinical Trials Search',
    'Semantic search over ClinicalTrials.gov trials via CKE.',
    'clinical,trials', 'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.SEARCH_CLINICAL_TRIALS',
    '{"query":"STRING","max_results":"INT"}',
    'VARCHAR',
    'CALL CATALOG.SEARCH_CLINICAL_TRIALS(''pembrolizumab melanoma'', 5)'
);

-- =============================================================================
-- Asset catalog search over the local ASSET_SEARCH Cortex Search service.
-- This one needs no Marketplace subscription: ASSET_SEARCH is built from
-- CATALOG.ASSETS by setup/06-cortex-services.sql.
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.SEARCH_ASSET_CATALOG(
    query       VARCHAR,
    max_results INT
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
COMMENT = 'TOOL:{"display_name":"Asset Catalog Search","description":"Semantic search over all registered datasets, tools, experiments, and notebooks.","domains":"all-domains,discovery","params":{"query":"STRING","max_results":"INT"},"return_type":"VARCHAR","example":"CALL CATALOG.SEARCH_ASSET_CATALOG(query, 10)"}'
AS
$$
import json

SERVICE = 'SCIENTIFIC_WORKBENCH.CATALOG.ASSET_SEARCH'
# Must match the service's indexed columns, which are uppercase.
COLUMNS = ['ASSET_ID', 'ASSET_NAME', 'ASSET_TYPE', 'DESCRIPTION', 'SCHEMA_NAME', 'OWNER']

def run(session, query: str, max_results: int) -> str:
    if not query or not str(query).strip():
        return json.dumps({'status': 'error', 'message': 'query is required'})

    limit = max(1, min(int(max_results or 10), 100))
    request = json.dumps({'query': str(query), 'columns': COLUMNS, 'limit': limit})

    try:
        rows = session.sql(
            "SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(?, ?) AS R",
            params=[SERVICE, request],
        ).collect()
        payload = json.loads(rows[0][0]) if rows and rows[0][0] else {}
    except Exception as e:
        return json.dumps({'status': 'error', 'message': str(e)[:500]})

    results = payload.get('results') or []
    # Drop the @scores block: it is search-engine metadata, not asset metadata.
    out = [{k: v for k, v in r.items() if k != '@scores'} for r in results if isinstance(r, dict)]
    return json.dumps({'status': 'success', 'count': len(out), 'results': out})
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'search_asset_catalog', 'Asset Catalog Search',
    'Semantic search over all registered platform assets (datasets, tools, experiments, notebooks).',
    'all-domains,discovery', 'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.SEARCH_ASSET_CATALOG',
    '{"query":"STRING","max_results":"INT"}',
    'VARCHAR',
    'CALL CATALOG.SEARCH_ASSET_CATALOG(''gene expression'', 10)'
);
