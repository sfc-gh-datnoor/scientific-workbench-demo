-- =============================================================================
-- setup/12-tool-knowledge.sql
-- Rich per-tool knowledge for agent-guided execution
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;

CREATE TABLE IF NOT EXISTS CATALOG.TOOL_KNOWLEDGE (
    TOOL_NAME         VARCHAR PRIMARY KEY,
    SCIENTIFIC_CONTEXT VARCHAR,
    PARAMETER_GUIDE   VARCHAR,
    EXAMPLE_INPUTS    VARIANT,
    OUTPUT_GUIDE      VARCHAR,
    COMMON_PITFALLS   VARCHAR,
    RELATED_TOOLS     ARRAY,
    EXAMPLE_SQL       VARCHAR
);
