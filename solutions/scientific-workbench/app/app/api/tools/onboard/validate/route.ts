import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

const ValidateSchema = z.object({
  name: z.string().min(1).max(128),
  source_type: z.enum(["rest_api", "python_code", "python_package", "git_repo", "existing_procedure", "spcs_container"]),
  source_config: z.record(z.string(), z.unknown()).optional().default({}),
  parameters: z.record(z.string(), z.unknown()).optional().default({}),
  return_type: z.string().max(256).optional().default("VARCHAR"),
})

export async function POST(req: NextRequest) {
  try {
    const body = ValidateSchema.safeParse(await req.json())
    if (!body.success) {
      const issues = body.error.issues.map(i => `${i.path.join(".")}: ${i.message}`)
      return Response.json({ valid: false, errors: issues })
    }

    const { name, source_type, source_config, parameters, return_type } = body.data
    const errors: string[] = []

    // Check name format
    if (!/^[a-z0-9_]+$/.test(name)) {
      errors.push("Name must be lowercase alphanumeric with underscores only")
    }

    // Check name uniqueness
    const existing = (await querySnowflake(
      `SELECT COUNT(*) AS CNT FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS WHERE name = ?`,
      { binds: [name] }
    )) as { CNT: number }[]
    if (existing[0]?.CNT > 0) {
      errors.push(`Tool name '${name}' already exists`)
    }

    // Check pending submissions
    const pending = (await querySnowflake(
      `SELECT COUNT(*) AS CNT FROM SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_TOOL_SUBMISSIONS
       WHERE tool_spec:name::VARCHAR = ? AND status = 'pending'`,
      { binds: [name] }
    )) as { CNT: number }[]
    if (pending[0]?.CNT > 0) {
      errors.push(`A submission for '${name}' is already pending approval`)
    }

    // Source-type-specific validation
    if (source_type === "rest_api") {
      const url = (source_config as Record<string, unknown>).url as string | undefined
      if (!url || !url.startsWith("https://")) {
        errors.push("REST API URL must use HTTPS")
      }
    }

    if (source_type === "python_code") {
      const code = (source_config as Record<string, unknown>).code as string | undefined
      if (!code || !code.trim()) {
        errors.push("Python code cannot be empty")
      }
      // Validate against banned patterns via the wrapper generator
      if (code && errors.length === 0) {
        try {
          const genRows = (await querySnowflake(
            `CALL SCIENTIFIC_WORKBENCH.CATALOG.GENERATE_TOOL_WRAPPER(?, ?, PARSE_JSON(?), PARSE_JSON(?), ?)`,
            { binds: [name, source_type, JSON.stringify(source_config), JSON.stringify(parameters), return_type] }
          )) as Record<string, unknown>[]
          const result = genRows[0] ? String(Object.values(genRows[0])[0]) : ""
          if (result.startsWith("ERROR")) {
            errors.push(result)
          }
        } catch (e) {
          errors.push("Code validation failed")
        }
      }
    }

    if (source_type === "existing_procedure") {
      const funcRef = (source_config as Record<string, unknown>).function_reference as string | undefined
      if (!funcRef) {
        errors.push("function_reference is required for existing_procedure")
      } else if (funcRef.split(".").length !== 3) {
        errors.push("function_reference must be fully qualified (DB.SCHEMA.NAME)")
      }
    }

    if (source_type === "spcs_container") {
      if (!(source_config as Record<string, unknown>).image_uri) {
        errors.push("image_uri is required for SPCS containers")
      }
    }

    return Response.json({
      valid: errors.length === 0,
      errors,
      requires_approval: source_type !== "existing_procedure",
    })
  } catch (e) {
    console.error(new Date().toISOString(), "[tool validate error]", e)
    return safeErrorResponse("Validation failed", 500)
  }
}
