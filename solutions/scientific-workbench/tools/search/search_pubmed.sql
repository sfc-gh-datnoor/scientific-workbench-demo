-- =============================================================================
-- tools/search/search_pubmed.sql
-- PubMed literature search over a Cortex Knowledge Extension (CKE).
--
-- FIXED 2026-09-08: the previous implementation called the service as
--     FROM TABLE(<service>!SEARCH(QUERY => ..., COLUMNS => ..., MAX_RESULTS => ...))
-- That method syntax is not available on this account and failed with
--     "Unknown user-defined table function ...PUBMED_CKE_SEARCH!SEARCH"
-- The failure was swallowed by the except block and returned as a JSON
-- {"status":"error"} payload inside a SUCCESSFUL procedure call, so the tool
-- looked healthy to anything that only checked whether the CALL threw.
-- Verified working entry point: SNOWFLAKE.CORTEX.SEARCH_PREVIEW(service, request).
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.SEARCH_PUBMED(
    query       VARCHAR,
    max_results INT
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
COMMENT = 'TOOL:{"display_name":"PubMed Literature Search","description":"Semantic search over PubMed Open Access articles via a CKE Marketplace subscription.","domains":"literature,all-domains","params":{"query":"STRING","max_results":"INT"},"return_type":"VARCHAR","example":"CALL CATALOG.SEARCH_PUBMED(query, 5)"}'
AS
$$
import json

SERVICE = 'SCIENTIFIC_WORKBENCH.CATALOG.PUBMED_CKE_SEARCH'
COLUMNS = ['PMID', 'TITLE', 'AUTHORS', 'JOURNAL', 'YEAR', 'ABSTRACT_EXCERPT']

def _search(session, service, request):
    """Call Cortex Search. Bind parameters, never string interpolation."""
    rows = session.sql(
        "SELECT SNOWFLAKE.CORTEX.SEARCH_PREVIEW(?, ?) AS R",
        params=[service, request],
    ).collect()
    return json.loads(rows[0][0]) if rows and rows[0][0] else {}

def _unavailable(service, detail):
    return json.dumps({
        'status': 'unavailable',
        'service': service,
        'message': (
            f'Cortex Search service {service} is not available in this account. '
            'PubMed search requires the PubMed Cortex Knowledge Extension from '
            'Snowflake Marketplace. Subscribe to it, then create the search '
            'service under that name. Until then this tool cannot return results.'
        ),
        'detail': detail[:300],
    })

def run(session, query: str, max_results: int) -> str:
    if not query or not str(query).strip():
        return json.dumps({'status': 'error', 'message': 'query is required'})

    limit = max(1, min(int(max_results or 5), 100))

    # Try with an explicit column list, then fall back to the service default.
    # A CKE's column names are set by its publisher, so a mismatch must degrade
    # rather than fail outright.
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
                return _unavailable(SERVICE, last)
            continue

        results = payload.get('results') or []
        rows = [{k: v for k, v in r.items() if k != '@scores'} for r in results if isinstance(r, dict)]
        if rows or 'results' in payload:
            return json.dumps({'status': 'success', 'count': len(rows), 'results': rows})

    return json.dumps({'status': 'error', 'message': (last or 'no results returned')[:500]})
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'search_pubmed', 'PubMed Literature Search',
    'Semantic search over PubMed articles via CKE. Returns PMIDs, titles, and excerpts.',
    'literature', 'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.SEARCH_PUBMED',
    '{"query":"STRING","max_results":"INT"}',
    'VARCHAR',
    'CALL CATALOG.SEARCH_PUBMED(''BRCA1 breast cancer'', 5)'
);
