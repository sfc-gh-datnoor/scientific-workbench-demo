import { querySnowflakeLongRunning } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

const RequestSchema = z.object({
  template_name: z.string().min(1).max(256),
  params: z.record(z.string(), z.unknown()).optional(),
})

export async function POST(req: NextRequest) {
  try {
    const body = RequestSchema.safeParse(await req.json())
    if (!body.success) {
      return safeErrorResponse("Invalid request: template_name is required", 400)
    }
    const { template_name, params } = body.data
    const paramsJson = JSON.stringify(params ?? {})

    const rows = await querySnowflakeLongRunning(
      `CALL SCIENTIFIC_WORKBENCH.WORKFLOWS.EXECUTE_TEMPLATE(?, PARSE_JSON(?))`,
      { binds: [template_name, paramsJson] }
    )
    const result = (rows[0] as { EXECUTE_TEMPLATE: unknown })?.EXECUTE_TEMPLATE ?? rows[0]
    return Response.json(result)
  } catch (e) {
    console.error(new Date().toISOString(), "[workflow run error]", e)
    return safeErrorResponse("Workflow execution failed", 500)
  }
}
