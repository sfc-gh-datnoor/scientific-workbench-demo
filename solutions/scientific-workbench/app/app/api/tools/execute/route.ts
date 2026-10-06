import { querySnowflake, querySnowflakeLongRunning } from "@/lib/snowflake"
import { quoteQualifiedName, safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

const RequestSchema = z.object({
  tool_name: z.string().min(1).max(256),
  params: z.record(z.string(), z.unknown()).optional(),
})

export async function POST(req: NextRequest) {
  try {
    const body = RequestSchema.safeParse(await req.json())
    if (!body.success) {
      return safeErrorResponse("Invalid request: tool_name is required", 400)
    }
    const { tool_name, params } = body.data

    // Bind variable for tool lookup
    const tools = (await querySnowflake(
      `SELECT function_reference, parameters, tool_type
       FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
       WHERE name = ? AND status = 'active'
       ORDER BY created_at DESC LIMIT 1`,
      { binds: [tool_name] }
    )) as { FUNCTION_REFERENCE: string; PARAMETERS: string; TOOL_TYPE: string }[]

    if (tools.length === 0) {
      return safeErrorResponse(`Tool not found`, 404)
    }

    const funcRef = tools[0].FUNCTION_REFERENCE
    const toolType = tools[0].TOOL_TYPE
    const paramSchema = JSON.parse(tools[0].PARAMETERS || "{}")

    // Validate funcRef as a safe qualified identifier
    let quotedFuncRef: string
    try {
      quotedFuncRef = quoteQualifiedName(funcRef)
    } catch {
      console.error(`[tool execute] Invalid function_reference in catalog: ${funcRef}`)
      return safeErrorResponse("Tool has invalid configuration", 500)
    }

    // Build parameterized CALL/SELECT with bind variables
    const paramNames = Object.keys(paramSchema)
    const binds: (string | number | null)[] = []
    const placeholders: string[] = []

    for (const p of paramNames) {
      const val = params?.[p]
      if (val === undefined || val === null || val === "") {
        const type = paramSchema[p]
        if (type === "STRING" || type === "VARCHAR") {
          binds.push("")
          placeholders.push("?")
        } else {
          placeholders.push("NULL")
        }
        continue
      }

      const type = paramSchema[p]
      if (type === "INT" || type === "FLOAT") {
        const num = Number(val)
        if (isNaN(num)) {
          return safeErrorResponse(`Parameter '${p}' must be a number`, 400)
        }
        binds.push(num)
        placeholders.push("?")
      } else if (type === "VARIANT" || type === "ARRAY") {
        binds.push(String(val))
        placeholders.push("PARSE_JSON(?)")
      } else {
        binds.push(String(val))
        placeholders.push("?")
      }
    }

    let sql: string
    if (toolType === "function") {
      sql = `SELECT * FROM TABLE(${quotedFuncRef}(${placeholders.join(", ")}))`
    } else {
      sql = `CALL ${quotedFuncRef}(${placeholders.join(", ")})`
    }

    const rows = await querySnowflakeLongRunning(sql, { binds })
    const result = rows[0] as Record<string, unknown> | undefined
    const firstValue = result ? Object.values(result)[0] : null

    return Response.json({
      success: true,
      result: firstValue,
      output_table: (params as Record<string, unknown>)?.output_table ?? null,
    })
  } catch (e) {
    console.error("[tool execute error]", e)
    return safeErrorResponse("Tool execution failed", 500)
  }
}
