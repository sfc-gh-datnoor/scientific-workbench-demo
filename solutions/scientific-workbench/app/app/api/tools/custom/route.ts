import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"

export const dynamic = "force-dynamic"

// GET — list custom (non-built-in) tools visible to the current user
export async function GET() {
  try {
    const rows = await querySnowflake(
      `SELECT tool_id, name, display_name, description, domain,
              tool_type, function_reference, parameters, return_type,
              compute_env, source_type, visibility,
              submitted_by, approved_by, approved_at, status, created_at
       FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
       WHERE source_type != 'built-in'
         AND status = 'active'
       ORDER BY created_at DESC`
    )
    return Response.json({ tools: rows })
  } catch (e) {
    console.error(new Date().toISOString(), "[custom tools list error]", e)
    return safeErrorResponse("Failed to list custom tools", 500)
  }
}
