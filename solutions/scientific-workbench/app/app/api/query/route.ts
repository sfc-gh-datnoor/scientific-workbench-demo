/**
 * Named-query endpoint.
 *
 * GET  /api/query — Returns CURRENT_USER/CURRENT_ROLE for both auth modes (health check)
 * POST /api/query — Executes a pre-defined named query with validated parameters
 *
 * Security: No arbitrary SQL is accepted. The client sends a query key
 * (e.g. "schema_tables") and the server maps it to a fixed SQL template.
 */

import { querySnowflake } from "@/lib/snowflake"
import { quoteIdentifier, safeErrorResponse } from "@/lib/validation"

export const dynamic = "force-dynamic"

const IDENTIFIER_RE = /^[A-Za-z_][A-Za-z0-9_$]{0,254}$/

function validateIdentifier(value: unknown, label: string): string {
  if (typeof value !== "string" || !IDENTIFIER_RE.test(value)) {
    throw new Error(`Invalid ${label}`)
  }
  return value.toUpperCase()
}

// Schemas whose tables may be previewed via "table_preview"
const ALLOWED_PREVIEW_SCHEMAS = new Set([
  "CATALOG", "WORKFLOWS", "GOVERNANCE", "PROVENANCE", "PROJECTS",
])

type NamedQueryHandler = (params: Record<string, unknown>) => Promise<{ sql: string; binds?: (string | number)[] }>

const NAMED_QUERIES: Record<string, NamedQueryHandler> = {
  schema_tables: async () => ({
    sql: `SELECT TABLE_SCHEMA, TABLE_NAME FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA') ORDER BY TABLE_SCHEMA, TABLE_NAME`,
  }),

  column_info: async (p) => {
    const schema = validateIdentifier(p.schema, "schema")
    const table = validateIdentifier(p.table, "table")
    return {
      sql: `SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION`,
      binds: [schema, table],
    }
  },

  table_preview: async (p) => {
    const schema = validateIdentifier(p.schema, "schema")
    const table = validateIdentifier(p.table, "table")
    if (!ALLOWED_PREVIEW_SCHEMAS.has(schema)) {
      throw new Error(`Schema ${schema} is not available for preview`)
    }
    const limit = Math.min(Number(p.limit) || 50, 200)
    const quoted = `"SCIENTIFIC_WORKBENCH".${quoteIdentifier(schema)}.${quoteIdentifier(table)}`
    return { sql: `SELECT * FROM ${quoted} LIMIT ${limit}` }
  },

  experiments_list: async () => ({
    sql: `SELECT r.RUN_ID, r.TEMPLATE_ID, t.DISPLAY_NAME AS TEMPLATE_NAME, r.STATUS, r.STARTED_AT, r.COMPLETED_AT, r.PARAMETERS, r.AGENT_SUMMARY, r.STEP_RESULTS FROM SCIENTIFIC_WORKBENCH.WORKFLOWS.RUNS r LEFT JOIN SCIENTIFIC_WORKBENCH.WORKFLOWS.TEMPLATES t ON r.TEMPLATE_ID = t.TEMPLATE_ID ORDER BY r.STARTED_AT DESC LIMIT 50`,
  }),

  assets_list: async () => ({
    sql: `SELECT ASSET_ID, NAME AS ASSET_NAME, TYPE AS ASSET_TYPE, PROGRAM, OWNER, DESCRIPTION, QUALITY_STATUS, CREATED_DATE AS CREATED_AT FROM SCIENTIFIC_WORKBENCH.CATALOG.ASSETS ORDER BY CREATED_DATE DESC NULLS LAST LIMIT 200`,
  }),

  promotion_log: async () => ({
    sql: `SELECT * FROM SCIENTIFIC_WORKBENCH.GOVERNANCE.PROMOTION_LOG ORDER BY ATTESTED_AT DESC NULLS LAST`,
  }),

  canary_assertions: async () => ({
    sql: `SELECT * FROM SCIENTIFIC_WORKBENCH.GOVERNANCE.CANARY_ASSERTIONS ORDER BY ASSERTION_ID`,
  }),

  provenance_log: async () => ({
    sql: `SELECT * FROM SCIENTIFIC_WORKBENCH.PROVENANCE.PROVENANCE_LOG ORDER BY LOGGED_AT DESC LIMIT 50`,
  }),

  experiment_results: async (p) => {
    const schema = validateIdentifier(p.schema, "schema")
    const table = validateIdentifier(p.table, "table")
    // Experiment output tables live in WORKFLOWS or PROJECTS schemas
    const allowedSchemas = new Set([...ALLOWED_PREVIEW_SCHEMAS, "SHARED_ANALYTICS"])
    if (!allowedSchemas.has(schema)) {
      throw new Error(`Schema ${schema} is not available for result preview`)
    }
    const db = p.database ? validateIdentifier(p.database, "database") : "SCIENTIFIC_WORKBENCH"
    const allowedDbs = new Set(["SCIENTIFIC_WORKBENCH", "WORKBENCH_PROJECTS"])
    if (!allowedDbs.has(db)) {
      throw new Error(`Database ${db} is not available for result preview`)
    }
    const quoted = `${quoteIdentifier(db)}.${quoteIdentifier(schema)}.${quoteIdentifier(table)}`
    return { sql: `SELECT * FROM ${quoted} LIMIT 100` }
  },
}

export async function GET() {
  try {
    const query = `SELECT CURRENT_USER() AS "USER", CURRENT_ROLE() AS ROLE`
    const serviceRows = await querySnowflake(query)

    let callerResult: { mode: string; result: Record<string, unknown> | null; error?: string }
    try {
      const callerRows = await querySnowflake(query, { callersRights: true })
      callerResult = { mode: "caller", result: (callerRows[0] as Record<string, unknown>) ?? null }
    } catch (e) {
      console.error("[query API] caller's rights query failed:", e)
      callerResult = { mode: "caller", result: null, error: "Caller's rights query failed" }
    }

    return Response.json({
      service: { mode: "service", result: (serviceRows[0] as Record<string, unknown>) ?? null },
      caller: callerResult,
    })
  } catch (e) {
    console.error("[query API] GET error:", e)
    return safeErrorResponse("Query failed", 500)
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const queryKey = body?.query

    if (!queryKey || typeof queryKey !== "string") {
      return Response.json({ error: "Missing 'query' field. Use a named query key." }, { status: 400 })
    }

    const handler = NAMED_QUERIES[queryKey]
    if (!handler) {
      return Response.json(
        { error: `Unknown query: ${queryKey}. Available: ${Object.keys(NAMED_QUERIES).join(", ")}` },
        { status: 400 }
      )
    }

    const params = (body.params ?? {}) as Record<string, unknown>
    const { sql, binds } = await handler(params)
    const rows = await querySnowflake(sql, binds ? { binds } : undefined)
    return Response.json({ rows })
  } catch (e) {
    console.error("[query API] POST error:", e)
    const message = e instanceof Error ? e.message : "Query failed"
    return Response.json({ error: message }, { status: 500 })
  }
}
