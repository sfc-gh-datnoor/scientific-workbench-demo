-- =============================================================================
-- tools/native/validate_gene_symbol.sql
-- HGNC gene symbol validator — SQL-based (no Python needed)
-- =============================================================================

CREATE OR REPLACE FUNCTION SCIENTIFIC_WORKBENCH.CATALOG.VALIDATE_GENE_SYMBOL(gene_symbol VARCHAR)
RETURNS TABLE (
    input_symbol    VARCHAR,
    approved_symbol VARCHAR,
    approved_name   VARCHAR,
    locus_type      VARCHAR,
    prev_symbols    VARCHAR,
    aliases         VARCHAR,
    status          VARCHAR
)
-- COMMENT must precede the AS clause in CREATE FUNCTION. It previously sat
-- after the closing $$, which Snowflake rejects with:
--   001003 (42000): syntax error unexpected 'COMMENT'.
COMMENT = 'TOOL:{"display_name":"Gene Symbol Validator","description":"Validates gene symbols against HGNC and returns approved symbol, name, and aliases. Catches deprecated/alias symbols.","domains":"genomics,validation","params":{"gene_symbol":"STRING"},"return_type":"TABLE","example":"SELECT * FROM TABLE(CATALOG.VALIDATE_GENE_SYMBOL(gene_symbol))"}'
AS
$$
    SELECT
        gene_symbol                        AS input_symbol,
        h.approved_symbol                  AS approved_symbol,
        h.approved_name                    AS approved_name,
        h.locus_type                       AS locus_type,
        h.prev_symbols                     AS prev_symbols,
        h.alias_symbols                    AS aliases,
        CASE
            WHEN h.approved_symbol = gene_symbol THEN 'EXACT_MATCH'
            WHEN CONTAINS(h.prev_symbols, gene_symbol) THEN 'PREV_SYMBOL'
            WHEN CONTAINS(h.alias_symbols, gene_symbol) THEN 'ALIAS_MATCH'
            ELSE 'NOT_FOUND'
        END                                AS status
    FROM WORKBENCH_REFERENCE.GENOMICS.HGNC_GENES h
    WHERE h.approved_symbol = gene_symbol
       OR CONTAINS(h.prev_symbols, gene_symbol)
       OR CONTAINS(h.alias_symbols, gene_symbol)
$$;

CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(
    'validate_gene_symbol', 'Gene Symbol Validator',
    'Validates gene symbols against HGNC. Returns approved symbol, name, locus type, and previous/alias symbols.',
    'genomics,validation', 'function',
    'SCIENTIFIC_WORKBENCH.CATALOG.VALIDATE_GENE_SYMBOL',
    '{"gene_symbol":"STRING"}',
    'TABLE(input_symbol,approved_symbol,approved_name,locus_type,prev_symbols,aliases,status)',
    'SELECT * FROM TABLE(CATALOG.VALIDATE_GENE_SYMBOL(''BRCA1''))'
);
