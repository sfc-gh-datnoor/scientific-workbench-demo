-- =============================================================================
-- 07-governance.sql
-- Provenance log, canary assertions, compound JOIN validation, classification
-- Run as SYSADMIN
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;

-- =============================================================================
-- 1. PROVENANCE LOG (immutable, append-only)
-- =============================================================================

CREATE TABLE IF NOT EXISTS PROVENANCE.PROVENANCE_LOG (
    log_id          NUMBER AUTOINCREMENT,
    logged_at       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    action_type     VARCHAR NOT NULL,  -- 'tool_execution','agent_query','nim_inference','decision','sql_query'
    target          VARCHAR NOT NULL,  -- tool name, agent name, or description
    parameters      VARIANT,
    result_summary  VARCHAR,
    confidence_tier VARCHAR,           -- 'grounded','inferred','speculative'
    user_name       VARCHAR DEFAULT CURRENT_USER(),
    interface       VARCHAR DEFAULT 'app', -- 'app','notebook','sql','sdk','api'
    session_id      VARCHAR DEFAULT CURRENT_SESSION(),
    duration_ms     NUMBER
)
CHANGE_TRACKING = TRUE
COMMENT = 'Immutable provenance log — every platform action recorded';

-- No UPDATE/DELETE grants on this table (enforced by not granting)

-- =============================================================================
-- 2. CANARY ASSERTIONS (biological plausibility testing)
-- =============================================================================

CREATE TABLE IF NOT EXISTS GOVERNANCE.CANARY_ASSERTIONS (
    assertion_id    VARCHAR NOT NULL PRIMARY KEY,
    query           VARCHAR NOT NULL,       -- NL question to ask the agent
    expected_answer VARCHAR NOT NULL,       -- Expected response (or key fact)
    domain          VARCHAR,               -- 'pharmacology','genomics','clinical'
    threshold       FLOAT DEFAULT 0.8,     -- Similarity threshold for pass
    active          BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Known-answer biological assertions for continuous validation';

-- Seed 20 canary assertions. MERGE keeps re-runs idempotent (Snowflake does
-- not enforce the PRIMARY KEY, so a plain INSERT duplicates rows per deploy).
MERGE INTO GOVERNANCE.CANARY_ASSERTIONS t
USING (SELECT column1 AS assertion_id, column2 AS query, column3 AS expected_answer, column4 AS domain FROM VALUES
('CAN-001', 'Does aspirin inhibit COX-2?', 'Yes, aspirin irreversibly inhibits cyclooxygenase-2 (COX-2)', 'pharmacology'),
('CAN-002', 'What is the target of imatinib?', 'BCR-ABL tyrosine kinase', 'pharmacology'),
('CAN-003', 'Is BRCA1 a tumor suppressor gene?', 'Yes, BRCA1 is a tumor suppressor involved in DNA repair', 'genomics'),
('CAN-004', 'Does sotorasib target KRAS G12C?', 'Yes, sotorasib (AMG 510) is a covalent inhibitor of KRAS G12C', 'pharmacology'),
('CAN-005', 'What pathway does EGFR activate?', 'RAS/MAPK and PI3K/AKT signaling pathways', 'genomics'),
('CAN-006', 'Is TP53 the most frequently mutated gene in cancer?', 'Yes, TP53 is mutated in approximately 50% of all cancers', 'genomics'),
('CAN-007', 'What is the mechanism of pembrolizumab?', 'Anti-PD-1 monoclonal antibody that blocks immune checkpoint', 'pharmacology'),
('CAN-008', 'Does metformin target AMPK?', 'Yes, metformin activates AMP-activated protein kinase (AMPK)', 'pharmacology'),
('CAN-009', 'Is HER2 amplification associated with breast cancer?', 'Yes, HER2 (ERBB2) amplification occurs in ~20% of breast cancers', 'genomics'),
('CAN-010', 'What is the function of VEGF?', 'Vascular endothelial growth factor promotes angiogenesis', 'genomics'),
('CAN-011', 'Does osimertinib target EGFR T790M?', 'Yes, osimertinib is a third-generation EGFR TKI targeting T790M resistance mutations', 'pharmacology'),
('CAN-012', 'Is KRAS undruggable?', 'No, KRAS G12C has been successfully targeted by sotorasib and adagrasib', 'pharmacology'),
('CAN-013', 'What chromosome is BRCA2 on?', 'Chromosome 13 (13q12.3)', 'genomics'),
('CAN-014', 'Does trastuzumab target HER2?', 'Yes, trastuzumab is a monoclonal antibody targeting HER2/ERBB2', 'pharmacology'),
('CAN-015', 'What is the role of mTOR in cell growth?', 'mTOR integrates nutrient/growth signals to regulate cell growth, proliferation, and survival', 'genomics'),
('CAN-016', 'Is venetoclax a BCL-2 inhibitor?', 'Yes, venetoclax selectively inhibits BCL-2 to induce apoptosis in CLL', 'pharmacology'),
('CAN-017', 'What does GWAS stand for?', 'Genome-Wide Association Study', 'genomics'),
('CAN-018', 'Is ALK rearrangement common in NSCLC?', 'ALK rearrangements occur in approximately 3-7% of NSCLC cases', 'clinical'),
('CAN-019', 'What is the primary endpoint in most oncology trials?', 'Overall survival (OS) or progression-free survival (PFS)', 'clinical'),
('CAN-020', 'Does CDK4/6 inhibition arrest cells in G1?', 'Yes, CDK4/6 inhibitors block G1-to-S phase transition', 'genomics')
) s
ON t.assertion_id = s.assertion_id
WHEN NOT MATCHED THEN INSERT (assertion_id, query, expected_answer, domain)
  VALUES (s.assertion_id, s.query, s.expected_answer, s.domain);

-- Canary results table (time-series)
CREATE TABLE IF NOT EXISTS GOVERNANCE.CANARY_RESULTS (
    run_id          VARCHAR,
    assertion_id    VARCHAR,
    run_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    passed          BOOLEAN,
    actual_answer   VARCHAR,
    similarity_score FLOAT,
    latency_ms      NUMBER
)
COMMENT = 'Time-series results of canary assertion runs';

-- Canary runner task (every 15 minutes)
CREATE OR REPLACE TASK GOVERNANCE.TASK_RUN_CANARIES
  WAREHOUSE = WORKBENCH_XS
  SCHEDULE = 'USING CRON */15 * * * * America/Los_Angeles'
  COMMENT = 'Run canary assertions every 15 min to detect regressions'
AS
  -- Placeholder: full implementation calls Discovery Agent per assertion
  INSERT INTO GOVERNANCE.CANARY_RESULTS (run_id, assertion_id, run_at, passed, latency_ms)
  SELECT UUID_STRING(), assertion_id, CURRENT_TIMESTAMP(), NULL, 0
  FROM GOVERNANCE.CANARY_ASSERTIONS WHERE active = TRUE;

-- =============================================================================
-- 3. COMPOUND JOIN VALIDATION
-- =============================================================================

CREATE OR REPLACE PROCEDURE GOVERNANCE.VALIDATE_COMPOUND_JOIN_KEYS(
    source_table VARCHAR, target_table VARCHAR, join_column VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    v_left_orphans  INT DEFAULT 0;
    v_right_orphans INT DEFAULT 0;
    v_passed        BOOLEAN DEFAULT FALSE;
BEGIN
    -- Bidirectional orphan check using RESULTSET + CURSOR pattern
    LET v_left_sql VARCHAR :=
        'SELECT COUNT(*) FROM ' || source_table
        || ' s LEFT ANTI JOIN ' || target_table
        || ' t ON s.' || join_column || ' = t.' || join_column;

    LET v_right_sql VARCHAR :=
        'SELECT COUNT(*) FROM ' || target_table
        || ' t LEFT ANTI JOIN ' || source_table
        || ' s ON t.' || join_column || ' = s.' || join_column;

    LET rs1 RESULTSET := (EXECUTE IMMEDIATE :v_left_sql);
    LET c1  CURSOR FOR rs1;
    OPEN c1;
    FETCH c1 INTO v_left_orphans;
    CLOSE c1;

    LET rs2 RESULTSET := (EXECUTE IMMEDIATE :v_right_sql);
    LET c2  CURSOR FOR rs2;
    OPEN c2;
    FETCH c2 INTO v_right_orphans;
    CLOSE c2;

    LET v_passed BOOLEAN := (v_left_orphans = 0 AND v_right_orphans = 0);

    IF (NOT v_passed) THEN
        INSERT INTO PROVENANCE.PROVENANCE_LOG (action_type, target, parameters, result_summary)
        VALUES ('join_validation_failure', join_column,
                OBJECT_CONSTRUCT('source', source_table, 'target', target_table,
                                 'left_orphans', v_left_orphans, 'right_orphans', v_right_orphans),
                'FAIL: ' || v_left_orphans::VARCHAR || ' left orphans, '
                          || v_right_orphans::VARCHAR || ' right orphans');
    END IF;

    RETURN OBJECT_CONSTRUCT(
        'passed',        v_passed,
        'source_table',  source_table,
        'target_table',  target_table,
        'join_column',   join_column,
        'left_orphans',  v_left_orphans,
        'right_orphans', v_right_orphans
    );
END;
$$;
