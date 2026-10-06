/**
 * General-purpose SQL query endpoint.
 *
 * GET  /api/query — Returns CURRENT_USER/CURRENT_ROLE for both auth modes (health check)
 * POST /api/query — Executes a read-only SQL query and returns rows
 */

import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"

export const dynamic = "force-dynamic"

const BLOCKED_PATTERNS = /^\s*(INSERT|UPDATE|DELETE|DROP|TRUNCATE|ALTER|CREATE|GRANT|REVOKE|MERGE|COPY|PUT|GET|REMOVE)\b/i

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
    const sql = body?.sql

    if (!sql || typeof sql !== "string" || sql.trim().length === 0) {
      return Response.json({ error: "Missing or empty 'sql' field" }, { status: 400 })
    }

    if (sql.length > 10000) {
      return Response.json({ error: "Query too long" }, { status: 400 })
    }

    if (BLOCKED_PATTERNS.test(sql.trim())) {
      return Response.json({ error: "Only SELECT queries are allowed" }, { status: 403 })
    }

    const rows = await querySnowflake(sql)
    return Response.json({ rows })
  } catch (e) {
    console.error("[query API] POST error:", e)
    const message = e instanceof Error ? e.message : "Query failed"
    return Response.json({ error: message }, { status: 500 })
  }
}
