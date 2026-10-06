/**
 * Named-query endpoint.
 *
 * GET  /api/query — Returns CURRENT_USER/CURRENT_ROLE for both auth modes (health check)
 * POST /api/query — Executes a pre-defined named query with validated parameters
 *
 * Security: No arbitrary SQL is accepted. The client sends a query key
 * (e.g. "schema_tables") and the server maps it to a fixed SQL template.
 * All query definitions live in lib/named-queries.ts.
 */

import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { resolveNamedQuery } from "@/lib/named-queries"

export const dynamic = "force-dynamic"

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

    const params = (body.params ?? {}) as Record<string, unknown>
    const { sql, binds } = resolveNamedQuery(queryKey, params)
    const rows = await querySnowflake(sql, binds ? { binds } : undefined)
    return Response.json({ rows })
  } catch (e) {
    console.error("[query API] POST error:", e)
    const message = e instanceof Error ? e.message : "Query failed"
    return Response.json({ error: message }, { status: 500 })
  }
}
