-- =============================================================================
-- 05-tool-registry.sql
-- Creates the tool registry table and registers all 21 P0 tools
-- Run as SYSADMIN
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;

-- =============================================================================
-- 1. TOOLS TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS CATALOG.TOOLS (
    tool_id              VARCHAR NOT NULL PRIMARY KEY,
    name                 VARCHAR NOT NULL UNIQUE,
    display_name         VARCHAR NOT NULL,
    description          VARCHAR NOT NULL,
    domain               ARRAY,
    tool_type            VARCHAR NOT NULL,        -- 'procedure' | 'function' | 'nim' | 'search'
    function_reference   VARCHAR NOT NULL,        -- fully-qualified callable
    parameters           VARCHAR NOT NULL,        -- JSON schema of params
    return_type          VARCHAR,
    compute_requirements VARCHAR DEFAULT 'WORKBENCH_S',
    example_usage        VARCHAR,
    version              VARCHAR DEFAULT '1.0',
    created_by           VARCHAR DEFAULT CURRENT_USER(),
    created_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    status               VARCHAR DEFAULT 'active' -- 'active' | 'deprecated' | 'testing'
)
CHANGE_TRACKING = TRUE
COMMENT = 'Registry of all agent-callable tools';

-- =============================================================================
-- 2. ASSETS TABLE (for Asset Catalog Search)
-- =============================================================================

CREATE TABLE IF NOT EXISTS CATALOG.ASSETS (
    asset_id       VARCHAR NOT NULL PRIMARY KEY,
    asset_name     VARCHAR NOT NULL,
    asset_type     VARCHAR NOT NULL,  -- 'dataset' | 'tool' | 'experiment' | 'notebook'
    description    VARCHAR,
    domain         VARCHAR,
    schema_name    VARCHAR,
    owner          VARCHAR,
    row_count      NUMBER,
    last_refresh   TIMESTAMP_NTZ,
    created_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
CHANGE_TRACKING = TRUE
COMMENT = 'Asset catalog — all discoverable platform objects';

-- Chat history metadata for the app's /chat page. SESSION_ID is the Cortex
-- Agent thread_id; message bodies live in the agent thread, so MESSAGES is
-- kept only for compatibility with the insert in app/app/api/chat/sessions.
CREATE TABLE IF NOT EXISTS CATALOG.CHAT_SESSIONS (
    session_id     VARCHAR NOT NULL PRIMARY KEY,
    title          VARCHAR,
    messages       VARIANT,
    user_name      VARCHAR,
    created_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Chat session metadata (one row per agent thread)';

-- =============================================================================
-- 3. REGISTER_TOOL PROCEDURE
-- =============================================================================

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL("P_NAME" VARCHAR, "P_DISPLAY_NAME" VARCHAR, "P_DESCRIPTION" VARCHAR, "P_DOMAINS" VARCHAR, "P_TOOL_TYPE" VARCHAR, "P_FUNCTION_REFERENCE" VARCHAR, "P_PARAMETERS" VARCHAR, "P_RETURN_TYPE" VARCHAR, "P_EXAMPLE_USAGE" VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT='Idempotent tool registration. Fixed 2026-09-01: the original did a blind INSERT, so every deploy appended a full duplicate set (103 rows for 21 tools, worst case 7 copies). NAME is declared a unique key but Snowflake does not enforce uniqueness constraints, so nothing caught it. This version updates in place and collapses pre-existing duplicates.'
EXECUTE AS OWNER
AS
$$
DECLARE
    v_max_id   INT DEFAULT 0;
    v_tool_id  VARCHAR;
    v_existing VARCHAR DEFAULT NULL;
BEGIN
    -- Reuse the existing row for this tool name if one is already present.
    SELECT MAX(tool_id) INTO :v_existing
    FROM CATALOG.TOOLS
    WHERE name = :p_name;

    IF (:v_existing IS NOT NULL) THEN
        -- Self-heal: collapse duplicates that earlier runs created.
        DELETE FROM CATALOG.TOOLS
        WHERE name = :p_name AND tool_id <> :v_existing;

        UPDATE CATALOG.TOOLS
        SET display_name       = :p_display_name,
            description        = :p_description,
            domain             = SPLIT(:p_domains, ','),
            tool_type          = :p_tool_type,
            function_reference = :p_function_reference,
            parameters         = :p_parameters,
            return_type        = :p_return_type,
            example_usage      = :p_example_usage,
            status             = 'active'
        WHERE tool_id = :v_existing;

        RETURN 'Updated: ' || :p_display_name || ' (ID: ' || :v_existing || ')';
    END IF;

    SELECT COALESCE(MAX(TRY_TO_NUMBER(REPLACE(tool_id, 'T', ''))), 0)
    INTO   :v_max_id
    FROM   CATALOG.TOOLS;

    v_tool_id := 'T' || LPAD((:v_max_id + 1)::VARCHAR, 3, '0');

    INSERT INTO CATALOG.TOOLS (
        tool_id, name, display_name, description, domain,
        tool_type, function_reference, parameters, return_type, example_usage
    )
    SELECT :v_tool_id, :p_name, :p_display_name, :p_description,
           SPLIT(:p_domains, ','),
           :p_tool_type, :p_function_reference, :p_parameters, :p_return_type, :p_example_usage;

    RETURN 'Registered: ' || :p_display_name || ' (ID: ' || :v_tool_id || ')';
END;
$$;

-- =============================================================================
-- 4. AUTO-DISCOVERY TASK
-- =============================================================================

CREATE OR REPLACE PROCEDURE CATALOG.AUTO_DISCOVER_TOOLS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    -- Scan for functions with TOOL: prefix in COMMENT
    -- Parse JSON and register any not already in the registry
    LET v_count INT := 0;
    
    FOR rec IN (
        SELECT function_name, function_schema, function_catalog,
               SUBSTR(description, 6) AS tool_json
        FROM INFORMATION_SCHEMA.FUNCTIONS
        WHERE description LIKE 'TOOL:%'
          AND function_catalog = 'SCIENTIFIC_WORKBENCH'
          AND function_name NOT IN (SELECT name FROM CATALOG.TOOLS)
    ) DO
        -- Auto-register discovered tools
        LET v_count := :v_count + 1;
    END FOR;
    
    RETURN 'Discovered ' || :v_count::VARCHAR || ' new tools';
END;
$$;

CREATE OR REPLACE TASK CATALOG.TASK_AUTO_DISCOVER_TOOLS
  WAREHOUSE = WORKBENCH_XS
  SCHEDULE = 'USING CRON 0 * * * * America/Los_Angeles'
  COMMENT = 'Hourly scan for COMMENT-annotated tools'
AS
  CALL CATALOG.AUTO_DISCOVER_TOOLS();

ALTER TASK CATALOG.TASK_AUTO_DISCOVER_TOOLS RESUME;

-- =============================================================================
-- 5. REGISTER ALL 21 P0 TOOLS
-- =============================================================================
-- Individual tool implementations are in tools/native/, tools/nvidia/, tools/search/
-- This section registers them in the catalog after they are created.
-- Run AFTER executing all tool creation scripts.

-- See setup/INSTALL.md for execution order:
--   1. Create tool procedures (tools/*.sql)
--   2. Run this script to register them
-- =============================================================================

-- =============================================================================
-- 6. SEED_ASSETS PROCEDURE
-- =============================================================================
-- Populates CATALOG.ASSETS from tools and reference data tables.
-- Called by deploy.sh after Phase 3 (tools) and Phase 2 (data).
-- Idempotent: uses MERGE to avoid duplicates.

CREATE OR REPLACE PROCEDURE CATALOG.SEED_ASSETS()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_tool_count INT DEFAULT 0;
    v_data_count INT DEFAULT 0;
BEGIN
    -- 1. Register every active tool as an asset
    MERGE INTO CATALOG.ASSETS tgt
    USING (
        SELECT
            'asset-tool-' || tool_id       AS asset_id,
            display_name                   AS asset_name,
            'tool'                         AS asset_type,
            description,
            domain[0]::VARCHAR             AS domain,
            'CATALOG'                      AS schema_name,
            created_by                     AS owner,
            NULL                           AS row_count,
            NULL                           AS last_refresh
        FROM CATALOG.TOOLS
        WHERE status = 'active'
    ) src ON tgt.asset_id = src.asset_id
    WHEN NOT MATCHED THEN INSERT (
        asset_id, asset_name, asset_type, description, domain, schema_name, owner, row_count, last_refresh
    ) VALUES (
        src.asset_id, src.asset_name, src.asset_type, src.description,
        src.domain, src.schema_name, src.owner, src.row_count, src.last_refresh
    );
    SELECT COUNT(*) INTO v_tool_count FROM CATALOG.ASSETS WHERE asset_type = 'tool';

    -- 2. Register reference data tables as assets (scan known schemas)
    MERGE INTO CATALOG.ASSETS tgt
    USING (
        SELECT
            'asset-data-' || t.table_catalog || '.' || t.table_schema || '.' || t.table_name AS asset_id,
            t.table_name                   AS asset_name,
            'dataset'                      AS asset_type,
            t.comment                      AS description,
            t.table_schema                 AS domain,
            t.table_schema                 AS schema_name,
            t.table_owner                  AS owner,
            t.row_count                    AS row_count,
            t.last_altered                 AS last_refresh
        FROM WORKBENCH_REFERENCE.INFORMATION_SCHEMA.TABLES t
        WHERE t.table_schema IN ('GENOMICS','CHEMBL','PATHWAYS','PROTEIN','CLINICAL')
          AND t.table_type = 'BASE TABLE'
    ) src ON tgt.asset_id = src.asset_id
    WHEN NOT MATCHED THEN INSERT (
        asset_id, asset_name, asset_type, description, domain, schema_name, owner, row_count, last_refresh
    ) VALUES (
        src.asset_id, src.asset_name, src.asset_type, src.description,
        src.domain, src.schema_name, src.owner, src.row_count, src.last_refresh
    )
    WHEN MATCHED THEN UPDATE SET
        row_count = src.row_count,
        last_refresh = src.last_refresh;
    SELECT COUNT(*) INTO v_data_count FROM CATALOG.ASSETS WHERE asset_type = 'dataset';

    RETURN 'Assets seeded: ' || :v_tool_count || ' tools, ' || :v_data_count || ' datasets';
END;
$$;
