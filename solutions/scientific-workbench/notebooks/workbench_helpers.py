"""Scientific Workbench — Notebook Helper Module

Import this in the first cell of any Snowflake Notebook in Workspaces:

    from workbench_helpers import Workbench
    wb = Workbench()

Provides governed access to:
  - Tool discovery and execution
  - Cortex Agent interaction
  - Dataset catalog and literature search
  - BioNeMo NIM inference
  - Provenance logging
"""

import json
from datetime import datetime
from typing import Any

from snowflake.snowpark import DataFrame as SnowparkDataFrame
from snowflake.snowpark.context import get_active_session


class Workbench:
    """Main interface to the Scientific Workbench from a notebook."""

    def __init__(
        self,
        database: str = "SCIENTIFIC_WORKBENCH",
        warehouse: str = "WORKBENCH_S",
    ):
        self.session = get_active_session()
        self.database = database
        self.warehouse = warehouse
        self._catalog_schema = f"{database}.CATALOG"
        self._results_schema = f"{database}.RESULTS"
        self._provenance_schema = f"{database}.PROVENANCE"
        self.session.sql(f"USE WAREHOUSE {warehouse}").collect()

    # ─── Tool Discovery ─────────────────────────────────────────────────

    def discover_tools(self, query: str, limit: int = 5) -> SnowparkDataFrame:
        """Semantic search over the tool registry by intent/domain."""
        return self.session.sql(f"""
            SELECT tool_id, display_name, description, domain, parameters, example_usage
            FROM TABLE(
                {self._catalog_schema}.TOOL_SEARCH!SEARCH(
                    '{query.replace("'", "''")}',
                    {limit}
                )
            )
        """)

    def list_tools(self, domain: str | None = None) -> SnowparkDataFrame:
        """List all registered tools, optionally filtered by domain."""
        sql = f"SELECT tool_id, display_name, description, domain, status FROM {self._catalog_schema}.TOOLS WHERE status = 'active'"
        if domain:
            sql += f" AND ARRAY_CONTAINS('{domain}'::VARIANT, domain)"
        return self.session.sql(sql)

    # ─── Tool Execution ──────────────────────────────────────────────────

    def run_tool(self, tool_name: str, **params) -> SnowparkDataFrame:
        """Execute a registered tool by name with the given parameters.

        Returns the result as a Snowpark DataFrame.
        """
        tool_info = self.session.sql(f"""
            SELECT function_reference, tool_type, parameters
            FROM {self._catalog_schema}.TOOLS
            WHERE name = '{tool_name}' AND status = 'active'
        """).collect()

        if not tool_info:
            raise ValueError(f"Tool '{tool_name}' not found or inactive in registry")

        row = tool_info[0]
        func_ref = row["FUNCTION_REFERENCE"]
        tool_type = row["TOOL_TYPE"]
        param_schema = json.loads(row["PARAMETERS"])

        # Build the call
        if tool_type == "procedure":
            args = ", ".join(
                f"'{params[k]}'" if isinstance(params.get(k), str) else str(params.get(k, "NULL"))
                for k in param_schema.keys()
            )
            call_sql = f"CALL {func_ref}({args})"
            self.session.sql(call_sql).collect()
            # Convention: procedures write to an output_table param
            if "output_table" in params:
                result = self.session.table(params["output_table"])
            else:
                result = self.session.sql("SELECT 'Tool executed successfully' AS status")
        else:
            # UDF/UDTF — build SELECT
            args = ", ".join(
                f"'{params[k]}'" if isinstance(params.get(k), str) else str(params.get(k, "NULL"))
                for k in param_schema.keys()
            )
            result = self.session.sql(f"SELECT * FROM TABLE({func_ref}({args}))")

        # Log to provenance
        self._log_provenance("tool_execution", tool_name, params)
        return result

    # ─── BioNeMo NIM Inference ───────────────────────────────────────────

    def run_nim(
        self,
        nim_name: str,
        *,
        smiles: str | None = None,
        target_pdb: str | None = None,
        sequence: str | None = None,
        n_samples: int = 10,
        **kwargs,
    ) -> SnowparkDataFrame:
        """Run a BioNeMo NIM (GenMol, DiffDock, Boltz-2, ProteinMPNN, RFdiffusion).

        Args:
            nim_name: One of 'genmol', 'diffdock', 'boltz2', 'proteinmpnn', 'rfdiffusion'
            smiles: Input SMILES (for genmol, diffdock)
            target_pdb: PDB ID or stage path (for diffdock, rfdiffusion)
            sequence: Protein sequence (for boltz2, proteinmpnn)
            n_samples: Number of outputs to generate
        """
        params = {
            "nim_name": nim_name,
            "smiles": smiles,
            "target_pdb": target_pdb,
            "sequence": sequence,
            "n_samples": n_samples,
            **kwargs,
        }
        params_json = json.dumps({k: v for k, v in params.items() if v is not None})

        result = self.session.sql(f"""
            CALL {self._catalog_schema}.RUN_NIM_INFERENCE(
                '{nim_name}',
                PARSE_JSON('{params_json.replace("'", "''")}')
            )
        """).collect()

        # Results written to a timestamped table
        output_table = f"{self._results_schema}.NIM_{nim_name.upper()}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        self._log_provenance("nim_inference", nim_name, params)
        return self.session.table(output_table)

    # ─── Agent Interaction ───────────────────────────────────────────────

    def ask_agent(
        self,
        query: str,
        agent: str = "DISCOVERY_AGENT",
    ) -> str:
        """Send a natural language query to a Cortex Agent.

        Returns the agent's text response.
        """
        escaped = query.replace("'", "''")
        result = self.session.sql(f"""
            SELECT SNOWFLAKE.CORTEX.INVOKE_AGENT(
                '{self._catalog_schema}.{agent}',
                '{escaped}'
            ) AS response
        """).collect()

        response = result[0]["RESPONSE"] if result else "No response from agent"
        self._log_provenance("agent_query", agent, {"query": query})
        return response

    # ─── Catalog & Literature Search ─────────────────────────────────────

    def search_catalog(self, query: str, limit: int = 10) -> SnowparkDataFrame:
        """Semantic search over the asset catalog (datasets, experiments, tools)."""
        return self.session.sql(f"""
            SELECT asset_id, asset_name, asset_type, description, schema_name, created_at
            FROM TABLE(
                {self._catalog_schema}.ASSET_SEARCH!SEARCH(
                    '{query.replace("'", "''")}',
                    {limit}
                )
            )
        """)

    def search_literature(self, query: str, limit: int = 5) -> SnowparkDataFrame:
        """Search PubMed articles via Cortex Search (5.2M indexed)."""
        return self.session.sql(f"""
            SELECT pmid, title, authors, journal, year, abstract_excerpt
            FROM TABLE(
                {self.database}.LITERATURE.PUBMED_SEARCH!SEARCH(
                    '{query.replace("'", "''")}',
                    {limit}
                )
            )
        """)

    def search_trials(self, query: str, limit: int = 5) -> SnowparkDataFrame:
        """Search ClinicalTrials.gov via Cortex Search."""
        return self.session.sql(f"""
            SELECT nct_id, title, phase, status, sponsor, conditions
            FROM TABLE(
                {self.database}.LITERATURE.TRIALS_SEARCH!SEARCH(
                    '{query.replace("'", "''")}',
                    {limit}
                )
            )
        """)

    # ─── Data Access Helpers ─────────────────────────────────────────────

    def query(self, sql: str) -> SnowparkDataFrame:
        """Execute arbitrary SQL and return as DataFrame. Logged to provenance."""
        self._log_provenance("sql_query", "ad_hoc", {"sql": sql[:500]})
        return self.session.sql(sql)

    def table(self, name: str) -> SnowparkDataFrame:
        """Get a table/view as a Snowpark DataFrame."""
        return self.session.table(name)

    # ─── Provenance & Decisions ──────────────────────────────────────────

    def log_decision(self, decision: str, evidence: str | None = None):
        """Record a scientific decision in the provenance log."""
        self._log_provenance(
            "decision",
            "scientist",
            {
                "decision": decision,
                "evidence": evidence or "",
            },
        )

    def get_provenance(self, session_id: str | None = None) -> SnowparkDataFrame:
        """Retrieve provenance log for the current session or a specific one."""
        sql = f"SELECT * FROM {self._provenance_schema}.PROVENANCE_LOG"
        if session_id:
            sql += f" WHERE session_id = '{session_id}'"
        sql += " ORDER BY logged_at DESC LIMIT 100"
        return self.session.sql(sql)

    # ─── Internal ────────────────────────────────────────────────────────

    def _log_provenance(self, action_type: str, target: str, params: dict[str, Any]):
        """Write an entry to the provenance log."""
        params_json = json.dumps(params, default=str).replace("'", "''")
        try:
            self.session.sql(f"""
                INSERT INTO {self._provenance_schema}.PROVENANCE_LOG
                    (logged_at, action_type, target, parameters, user_name, interface)
                VALUES (
                    CURRENT_TIMESTAMP(),
                    '{action_type}',
                    '{target}',
                    PARSE_JSON('{params_json}'),
                    CURRENT_USER(),
                    'notebook'
                )
            """).collect()
        except Exception:
            pass  # Don't fail user's work if provenance logging has issues
