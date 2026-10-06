-- =============================================================================
-- tools/native/run_differential_expression.sql
-- Deploys the DE analysis stored procedure and registers it in the tool catalog
-- Runtime: Snowpark Python 3.10 on WORKBENCH_S warehouse
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.RUN_DIFFERENTIAL_EXPRESSION(
    expression_table VARCHAR,
    patients_table   VARCHAR,
    group_column     VARCHAR,
    group_a          VARCHAR,
    group_b          VARCHAR,
    output_table     VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'scipy', 'numpy', 'pandas')
HANDLER = 'run'
COMMENT = 'TOOL:{"display_name":"Differential Expression Analysis","description":"Compares gene expression between two patient groups using Mann-Whitney U test with Benjamini-Hochberg FDR correction. Identifies significantly up/down regulated genes.","domains":"genomics,omics,transcriptomics","params":{"expression_table":"STRING","patients_table":"STRING","group_column":"STRING","group_a":"STRING","group_b":"STRING","output_table":"STRING"},"return_type":"VARCHAR","example":"CALL CATALOG.RUN_DIFFERENTIAL_EXPRESSION(expr_table, patients_table, group_col, group_a, group_b, output_table)"}'
AS
$$
import numpy as np
import pandas as pd
from scipy import stats
from snowflake.snowpark.context import get_active_session

def benjamini_hochberg(pvalues):
    """BH FDR correction."""
    n = len(pvalues)
    ranked = np.argsort(pvalues)
    pvalues_arr = np.array(pvalues)
    padj = np.empty(n)
    for k, i in enumerate(ranked):
        padj[i] = pvalues_arr[i] * n / (k + 1)
    # Enforce monotonicity
    for i in range(n - 2, -1, -1):
        padj[ranked[i]] = min(padj[ranked[i]], padj[ranked[i + 1]])
    return np.minimum(padj, 1.0).tolist()

def run(session, expression_table: str, patients_table: str,
        group_column: str, group_a: str, group_b: str,
        output_table: str) -> str:
    # Validate inputs
    for t in [expression_table, patients_table]:
        if not t or '.' not in t:
            return f"ERROR: Table '{t}' must be fully qualified (db.schema.table)"

    # Load patients
    patients_sql = f"""
        SELECT patient_id, {group_column}
        FROM {patients_table}
        WHERE {group_column} IN ('{group_a}', '{group_b}')
    """
    patients_df = session.sql(patients_sql).to_pandas()

    ids_a = patients_df[patients_df[group_column.upper()] == group_a]['PATIENT_ID'].tolist()
    ids_b = patients_df[patients_df[group_column.upper()] == group_b]['PATIENT_ID'].tolist()

    if not ids_a or not ids_b:
        return f"ERROR: One or both groups are empty. Found {len(ids_a)} in '{group_a}', {len(ids_b)} in '{group_b}'"

    # Load expression (wide format: patient_id, gene_symbol, expression_value)
    id_list_a = ", ".join(f"'{x}'" for x in ids_a)
    id_list_b = ", ".join(f"'{x}'" for x in ids_b)

    expr_sql = f"""
        SELECT gene_symbol,
               patient_id,
               expression_value
        FROM {expression_table}
        WHERE patient_id IN ({id_list_a}, {id_list_b})
    """
    expr_df = session.sql(expr_sql).to_pandas()
    expr_df.columns = [c.upper() for c in expr_df.columns]

    # Pivot to genes x patients
    pivoted = expr_df.pivot_table(
        index='GENE_SYMBOL', columns='PATIENT_ID', values='EXPRESSION_VALUE'
    )

    # Mann-Whitney U test per gene
    results = []
    genes = pivoted.index.tolist()

    for gene in genes:
        row = pivoted.loc[gene]
        vals_a = row[[p for p in ids_a if p in row.index]].dropna().tolist()
        vals_b = row[[p for p in ids_b if p in row.index]].dropna().tolist()

        if len(vals_a) < 3 or len(vals_b) < 3:
            continue

        stat, pval = stats.mannwhitneyu(vals_a, vals_b, alternative='two-sided')
        mean_a = float(np.mean(vals_a))
        mean_b = float(np.mean(vals_b))
        log2fc = float(np.log2(mean_a + 1) - np.log2(mean_b + 1))

        results.append({
            'GENE_SYMBOL': gene,
            'LOG2FC': round(log2fc, 4),
            'PVALUE': float(pval),
            'MEAN_A': round(mean_a, 4),
            'MEAN_B': round(mean_b, 4),
            'DIRECTION': 'UP' if log2fc > 0 else 'DOWN'
        })

    if not results:
        return "WARNING: No genes with sufficient samples in both groups"

    # BH correction
    pvalues = [r['PVALUE'] for r in results]
    padj_vals = benjamini_hochberg(pvalues)
    for i, r in enumerate(results):
        r['PADJ'] = round(padj_vals[i], 6)

    # Write results
    result_df = pd.DataFrame(results)
    result_sp = session.create_dataframe(result_df)
    result_sp.write.mode('overwrite').save_as_table(output_table)

    n_sig = sum(1 for r in results if r['PADJ'] < 0.05)
    return f"SUCCESS: {len(results)} genes tested, {n_sig} significant at FDR < 0.05. Results in {output_table}"
$$;

-- Register in tool catalog
CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'run_differential_expression',
    'Differential Expression Analysis',
    'Compares gene expression between two patient groups using Mann-Whitney U test with Benjamini-Hochberg FDR correction. Returns genes with log2FC, p-values, and direction.',
    'genomics,omics,transcriptomics',
    'procedure',
    'SCIENTIFIC_WORKBENCH.CATALOG.RUN_DIFFERENTIAL_EXPRESSION',
    '{"expression_table":"STRING","patients_table":"STRING","group_column":"STRING","group_a":"STRING","group_b":"STRING","output_table":"STRING"}',
    'VARCHAR',
    'CALL CATALOG.RUN_DIFFERENTIAL_EXPRESSION(expr_table, patients_table, group_col, group_a, group_b, output_table)'
);
