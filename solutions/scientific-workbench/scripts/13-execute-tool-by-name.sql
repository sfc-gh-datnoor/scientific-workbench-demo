-- =============================================================================
-- setup/13-execute-tool-by-name.sql
-- CATALOG.EXECUTE_TOOL_BY_NAME: resolve a registered tool by name and invoke it.
--
-- WHY THIS EXISTS
-- The Discovery Agent's orchestration instructions (engine/sql/create_workflow_runner.sql)
-- tell the agent to run tools with:
--     CALL SCIENTIFIC_WORKBENCH.CATALOG.EXECUTE_TOOL_BY_NAME('ToolName', PARSE_JSON('{...}'))
-- That procedure was never created, so every agent-driven tool call failed. This
-- file supplies it.
--
-- DESIGN NOTES
--   * Argument ORDER comes from INFORMATION_SCHEMA.PROCEDURES.ARGUMENT_SIGNATURE,
--     not from CATALOG.TOOLS.PARAMETERS. Snowflake normalises OBJECT keys into
--     alphabetical order, so the registry's PARAMETERS object cannot be trusted
--     for positional arguments (run_genmol would bind n_samples before seed_smiles).
--   * Name resolution is deliberately forgiving: the agent is prompted with
--     display names ("GenMol", "Boltz2") while the registry keys are snake_case
--     ("run_genmol"), so both forms, and a `run_`-prefixed fallback, resolve.
--   * EXECUTE AS CALLER so the invoker's own grants are enforced. This procedure
--     must not become a privilege-escalation path to every tool in the registry.
--   * Every invocation is written to PROVENANCE.PROVENANCE_LOG, including failures.
-- =============================================================================

USE DATABASE SCIENTIFIC_WORKBENCH;
USE SCHEMA CATALOG;

CREATE OR REPLACE PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.EXECUTE_TOOL_BY_NAME(
  P_TOOL_NAME VARCHAR,
  P_PARAMS VARIANT
)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
COMMENT = 'Resolve a registered tool by name and invoke it with named JSON parameters'
EXECUTE AS CALLER
AS
$$
import json
import re
import time


def _norm(value):
    """Collapse a tool name to comparable form: lowercase alphanumerics only."""
    return re.sub(r"[^a-z0-9]", "", (value or "").lower())


def _resolve_tool(session, requested):
    """Find one active registry row matching the requested name.

    Tries, in order: exact name, case-insensitive name, display_name,
    normalised name/display_name, then a `run_`-prefixed retry.
    """
    rows = session.sql(
        """
        SELECT name, display_name, tool_type, function_reference, return_type
        FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
        WHERE status = 'active'
        """
    ).collect()

    target = _norm(requested)
    candidates = [target]
    if not target.startswith("run"):
        candidates.append("run" + target)

    for want in candidates:
        for r in rows:
            if _norm(r["NAME"]) == want or _norm(r["DISPLAY_NAME"]) == want:
                return r
    return None


def _parse_signature(signature):
    """Turn '(SEED_SMILES VARCHAR, N_SAMPLES NUMBER)' into [(name, type), ...].

    Order is significant: it is the positional order the procedure declares.
    """
    inner = (signature or "").strip()
    if inner.startswith("("):
        inner = inner[1:]
    if inner.endswith(")"):
        inner = inner[:-1]
    args = []
    for part in inner.split(","):
        part = part.strip()
        if not part:
            continue
        bits = part.split()
        if len(bits) >= 2:
            args.append((bits[0].upper(), " ".join(bits[1:]).upper()))
        elif bits:
            args.append((bits[0].upper(), "VARCHAR"))
    return args


def _signature_for(session, function_reference):
    """Read the declared argument signature for a procedure FQN."""
    parts = function_reference.split(".")
    if len(parts) != 3:
        return None
    db, schema, name = [p.strip('"') for p in parts]
    rows = session.sql(
        f"""
        SELECT ARGUMENT_SIGNATURE
        FROM {db}.INFORMATION_SCHEMA.PROCEDURES
        WHERE PROCEDURE_SCHEMA = '{schema.upper()}'
          AND PROCEDURE_NAME = '{name.upper()}'
        ORDER BY LENGTH(ARGUMENT_SIGNATURE) DESC
        LIMIT 1
        """
    ).collect()
    return rows[0]["ARGUMENT_SIGNATURE"] if rows else None


def _literal(value, sql_type):
    """Render a Python value as a SQL literal for the declared column type."""
    if value is None:
        return "NULL"

    numeric = any(
        t in sql_type for t in ("NUMBER", "INT", "FLOAT", "DOUBLE", "DECIMAL", "NUMERIC", "REAL")
    )
    if numeric:
        if isinstance(value, bool):
            return "1" if value else "0"
        try:
            text = str(value).strip()
            # Reject anything that is not a plain number: this value is
            # interpolated into SQL, so it must not carry arbitrary text.
            if not re.fullmatch(r"[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?", text):
                raise ValueError(f"non-numeric value for {sql_type}: {text[:40]}")
            return text
        except Exception as exc:
            raise ValueError(str(exc))

    if "BOOLEAN" in sql_type:
        return "TRUE" if value else "FALSE"

    if any(t in sql_type for t in ("VARIANT", "OBJECT", "ARRAY")):
        payload = json.dumps(value).replace("'", "''")
        return f"PARSE_JSON('{payload}')"

    text = value if isinstance(value, str) else json.dumps(value)
    return "'" + text.replace("'", "''") + "'"


def _log(session, action, target, params, summary, tier, duration_ms):
    """Best-effort provenance write. Never let logging mask the real result."""
    try:
        payload = json.dumps(params or {}).replace("'", "''")
        note = (summary or "")[:4000].replace("'", "''")
        session.sql(
            f"""
            INSERT INTO SCIENTIFIC_WORKBENCH.PROVENANCE.PROVENANCE_LOG
              (ACTION_TYPE, TARGET, PARAMETERS, RESULT_SUMMARY, CONFIDENCE_TIER,
               INTERFACE, DURATION_MS)
            SELECT '{action}', '{target.replace("'", "''")}', PARSE_JSON('{payload}'),
                   '{note}', '{tier}', 'agent', {int(duration_ms)}
            """
        ).collect()
    except Exception:
        pass


def run(session, p_tool_name, p_params):
    started = time.time()

    if not p_tool_name or not str(p_tool_name).strip():
        return {"status": "ERROR", "error": "Tool name is required"}

    requested = str(p_tool_name).strip()

    # P_PARAMS arrives as a dict when called with PARSE_JSON, but tolerate a
    # JSON string so the agent can pass either form.
    params = p_params
    if isinstance(params, str):
        try:
            params = json.loads(params) if params.strip() else {}
        except Exception:
            return {"status": "ERROR", "error": "P_PARAMS is not valid JSON"}
    if params is None:
        params = {}
    if not isinstance(params, dict):
        return {"status": "ERROR", "error": "P_PARAMS must be a JSON object"}

    tool = _resolve_tool(session, requested)
    if tool is None:
        available = [
            r["NAME"]
            for r in session.sql(
                "SELECT name FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS "
                "WHERE status = 'active' ORDER BY name"
            ).collect()
        ]
        _log(session, "TOOL_CALL_FAILED", requested, params, "unknown tool", "SPECULATIVE",
             (time.time() - started) * 1000)
        return {
            "status": "ERROR",
            "error": f"No active tool matches '{requested}'",
            "available_tools": available,
        }

    resolved_name = tool["NAME"]
    func_ref = tool["FUNCTION_REFERENCE"]
    tool_type = (tool["TOOL_TYPE"] or "procedure").lower()

    if tool_type != "procedure":
        # Table functions take a different call shape and are queried, not CALLed.
        return {
            "status": "ERROR",
            "error": (
                f"'{resolved_name}' is registered as a {tool_type}, not a procedure. "
                f"Query it directly, e.g. SELECT * FROM TABLE({func_ref}(...))."
            ),
            "function_reference": func_ref,
        }

    signature = _signature_for(session, func_ref)
    if not signature:
        return {
            "status": "ERROR",
            "error": f"Could not read argument signature for {func_ref}",
        }

    declared = _parse_signature(signature)

    # Match caller-supplied keys to declared argument names, case-insensitively.
    supplied = {str(k).upper(): v for k, v in params.items()}
    bound, missing, used = [], [], set()
    for arg_name, arg_type in declared:
        if arg_name in supplied:
            used.add(arg_name)
            try:
                bound.append(_literal(supplied[arg_name], arg_type))
            except ValueError as exc:
                return {
                    "status": "ERROR",
                    "error": f"Invalid value for {arg_name}: {exc}",
                    "expected_type": arg_type,
                }
        else:
            bound.append("NULL")
            missing.append(arg_name)

    unknown = sorted(set(supplied) - used)
    call_sql = f"CALL {func_ref}(" + ", ".join(bound) + ")"

    try:
        rows = session.sql(call_sql).collect()
    except Exception as exc:
        elapsed = (time.time() - started) * 1000
        _log(session, "TOOL_CALL_FAILED", resolved_name, params, str(exc)[:1000],
             "SPECULATIVE", elapsed)
        return {
            "status": "ERROR",
            "tool": resolved_name,
            "error": str(exc)[:2000],
            "call": call_sql[:2000],
        }

    raw = rows[0][0] if rows and len(rows[0]) > 0 else None
    result = raw
    if isinstance(raw, str):
        # Most NIM procedures return a JSON string. Surface it as an object when
        # possible so the agent can read fields without a second parse step.
        try:
            result = json.loads(raw)
        except Exception:
            result = raw

    elapsed = (time.time() - started) * 1000
    _log(session, "TOOL_CALL", resolved_name, params, str(result)[:2000], "GROUNDED", elapsed)

    out = {
        "status": "OK",
        "tool": resolved_name,
        "requested_name": requested,
        "function_reference": func_ref,
        "duration_ms": int(elapsed),
        "result": result,
    }
    if missing:
        out["defaulted_to_null"] = missing
    if unknown:
        out["ignored_parameters"] = unknown
    return out
$$;

-- Scientists and admins invoke tools through the agent, so both need USAGE.
GRANT USAGE ON PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.EXECUTE_TOOL_BY_NAME(VARCHAR, VARIANT)
  TO ROLE WORKBENCH_SCIENTIST;
GRANT USAGE ON PROCEDURE SCIENTIFIC_WORKBENCH.CATALOG.EXECUTE_TOOL_BY_NAME(VARCHAR, VARIANT)
  TO ROLE WORKBENCH_ADMIN;
