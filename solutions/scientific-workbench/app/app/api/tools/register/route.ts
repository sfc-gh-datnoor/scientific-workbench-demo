import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

const RequestSchema = z.object({
  name: z.string().min(1).max(256),
  display_name: z.string().max(256).optional().default(""),
  description: z.string().max(4000).optional().default(""),
  domains: z.string().max(1000).optional().default(""),
  tool_type: z.string().max(64).optional().default("procedure"),
  function_reference: z.string().min(1).max(512),
  parameters: z.string().max(4000).optional().default("{}"),
  return_type: z.string().max(256).optional().default(""),
  example_usage: z.string().max(4000).optional().default(""),
})

export async function POST(req: NextRequest) {
  try {
    const body = RequestSchema.safeParse(await req.json())
    if (!body.success) {
      return safeErrorResponse("Invalid request: " + body.error.issues[0]?.message, 400)
    }
    const d = body.data

    const rows = await querySnowflake(
      `CALL SCIENTIFIC_WORKBENCH.CATALOG.REGISTER_TOOL(?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      { binds: [d.name, d.display_name, d.description, d.domains, d.tool_type, d.function_reference, d.parameters, d.return_type, d.example_usage] }
    )
    const result = rows[0] as { REGISTER_TOOL: string } | undefined

    return Response.json({ message: result?.REGISTER_TOOL ?? "Tool registered" })
  } catch (e) {
    console.error(new Date().toISOString(), "[tool register error]", e)
    return safeErrorResponse("Registration failed", 500)
  }
}
