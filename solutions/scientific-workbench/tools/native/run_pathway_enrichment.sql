-- =============================================================================
-- tools/native/run_pathway_enrichment.sql
-- Pathway Over-Representation Analysis against MSigDB Hallmark gene sets
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_PATHWAY_ENRICHMENT(
    de_results_table VARCHAR,
    fdr_threshold    FLOAT,
    output_table     VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'scipy', 'numpy', 'pandas')
HANDLER = 'run'
COMMENT = 'TOOL:{"display_name":"Pathway Enrichment (ORA)","description":"Over-representation analysis of DE genes against MSigDB Hallmark gene sets using Fisher exact test with BH-FDR correction.","domains":"genomics,pathways,enrichment","params":{"de_results_table":"STRING","fdr_threshold":"FLOAT","output_table":"STRING"},"return_type":"VARCHAR","example":"CALL CATALOG.RUN_PATHWAY_ENRICHMENT(de_table, 0.05, output_table)"}'
AS
$$
import numpy as np
import pandas as pd
from scipy import stats
from snowflake.snowpark.context import get_active_session

def benjamini_hochberg(pvalues):
    n = len(pvalues)
    if n == 0:
        return []
    ranked = np.argsort(pvalues)
    pvalues_arr = np.array(pvalues)
    padj = np.empty(n)
    for k, i in enumerate(ranked):
        padj[i] = pvalues_arr[i] * n / (k + 1)
    for i in range(n - 2, -1, -1):
        padj[ranked[i]] = min(padj[ranked[i]], padj[ranked[i + 1]])
    return np.minimum(padj, 1.0).tolist()

def run(session, de_results_table: str, fdr_threshold: float, output_table: str) -> str:
    # Load significant DE genes
    de_sql = f"""
        SELECT gene_symbol, direction
        FROM {de_results_table}
        WHERE padj < {fdr_threshold}
          AND ABS(log2fc) > 1
    """
    de_df = session.sql(de_sql).to_pandas()
    de_df.columns = [c.upper() for c in de_df.columns]
    sig_genes = set(de_df['GENE_SYMBOL'].tolist())

    if len(sig_genes) < 5:
        return f"WARNING: Too few significant genes ({len(sig_genes)}) for pathway analysis"

    # Load MSigDB Hallmarks
    msig_sql = """
        SELECT gs.gene_set_name, gsm.gene_symbol
        FROM WORKBENCH_REFERENCE.PATHWAYS.GENE_SETS gs
        JOIN WORKBENCH_REFERENCE.PATHWAYS.GENE_SET_MEMBERS gsm
          ON gs.gene_set_id = gsm.gene_set_id
        WHERE gs.collection = 'HALLMARKS'
    """
    msig_df = session.sql(msig_sql).to_pandas()
    msig_df.columns = [c.upper() for c in msig_df.columns]

    # All genes in universe (all genes tested in DE)
    all_genes_sql = f"SELECT DISTINCT gene_symbol FROM {de_results_table}"
    all_genes_df = session.sql(all_genes_sql).to_pandas()
    universe = set(all_genes_df.iloc[:, 0].tolist())
    N = len(universe)

    results = []
    for pathway_name, group_df in msig_df.groupby('GENE_SET_NAME'):
        pathway_genes = set(group_df['GENE_SYMBOL'].tolist())
        K = len(pathway_genes & universe)   # pathway genes in universe
        n = len(sig_genes)                  # DE genes
        k = len(sig_genes & pathway_genes)  # overlap

        if K < 5 or k == 0:
            continue

        # Fisher exact test (2x2 contingency)
        cont = [[k, n - k],
                [K - k, N - K - (n - k)]]
        _, pval = stats.fisher_exact(cont, alternative='greater')

        overlap_genes = ','.join(sorted(sig_genes & pathway_genes))
        results.append({
            'PATHWAY_NAME': pathway_name,
            'PVALUE': float(pval),
            'OVERLAP_COUNT': k,
            'PATHWAY_SIZE': K,
            'UNIVERSE_SIZE': N,
            'OVERLAP_GENES': overlap_genes
        })

    if not results:
        return "WARNING: No enriched pathways found"

    padj_vals = benjamini_hochberg([r['PVALUE'] for r in results])
    for i, r in enumerate(results):
        r['FDR'] = round(padj_vals[i], 6)

    result_df = pd.DataFrame(results)
    result_sp = session.create_dataframe(result_df)
    result_sp.write.mode('overwrite').save_as_table(output_table)

    n_sig = sum(1 for r in results if r['FDR'] < 0.05)
    return f"SUCCESS: {len(results)} pathways tested, {n_sig} significant at FDR < 0.05. Results in {output_table}"
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_pathway_enrichment', 'Pathway Enrichment (ORA)',
    'Over-representation analysis of DE genes against MSigDB Hallmark gene sets using Fisher exact test with BH-FDR correction.',
    'genomics,pathways,enrichment', 'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_PATHWAY_ENRICHMENT',
    '{"de_results_table":"STRING","fdr_threshold":"FLOAT","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_PATHWAY_ENRICHMENT(de_table, 0.05, output_table)'
);
