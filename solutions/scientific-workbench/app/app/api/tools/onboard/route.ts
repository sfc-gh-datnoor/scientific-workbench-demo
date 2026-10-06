import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

const SourceConfigSchema = z.object({
  url: z.string().url().optional(),
  method: z.enum(["GET", "POST", "PUT"]).optional(),
  auth_type: z.enum(["none", "api_key", "bearer"]).optional(),
  auth_header: z.string().max(128).optional(),
  headers: z.record(z.string(), z.string()).optional(),
  response_path: z.string().max(512).optional(),
  code: z.string().max(50000).optional(),
  packages: z.array(z.string().max(64)).max(20).optional(),
  function_reference: z.string().max(512).optional(),
  image_uri: z.string().max(512).optional(),
  endpoint_path: z.string().max(256).optional(),
  port: z.number().int().min(1).max(65535).optional(),
  compute_pool: z.string().max(128).optional(),
  env_vars: z.record(z.string(), z.string()).optional(),
  display_name: z.string().max(256).optional(),
  package_name: z.string().max(128).optional(),
  capability_name: z.string().max(128).optional(),
  capability_description: z.string().max(4000).optional(),
  repo_url: z.string().url().optional(),
  entry_point: z.string().max(512).optional(),
}).passthrough()

const OnboardSchema = z.object({
  name: z.string().min(1).max(128).regex(/^[a-z0-9_]+$/, "Name must be lowercase alphanumeric with underscores"),
  display_name: z.string().max(256).optional().default(""),
  description: z.string().max(4000).optional().default(""),
  domains: z.array(z.string().max(64)).max(10).optional().default(["custom"]),
  source_type: z.enum(["rest_api", "python_code", "python_package", "git_repo", "existing_procedure", "spcs_container"]),
  source_config: SourceConfigSchema,
  parameters: z.record(z.string(), z.union([
    z.string(),
    z.object({
      type: z.string(),
      description: z.string().optional(),
      required: z.boolean().optional(),
      default: z.unknown().optional(),
    })
  ])).optional().default({}),
  return_type: z.string().max(256).optional().default("VARCHAR"),
  compute_env: z.enum(["warehouse", "gpu_nim", "spcs_container"]).optional().default("warehouse"),
  visibility: z.enum(["personal", "shared", "org"]).optional().default("shared"),
  example_usage: z.string().max(4000).optional().default(""),
})

export async function POST(req: NextRequest) {
  try {
    const body = OnboardSchema.safeParse(await req.json())
    if (!body.success) {
      const issues = body.error.issues.map(i => `${i.path.join(".")}: ${i.message}`)
      return safeErrorResponse(`Validation failed: ${issues[0]}`, 400)
    }

    const spec = body.data

    // Pass display_name into source_config for wrapper generator
    if (spec.display_name && !spec.source_config.display_name) {
      spec.source_config.display_name = spec.display_name
    }

    const rows = await querySnowflake(
      `CALL SCIENTIFIC_WORKBENCH.CATALOG.ONBOARD_CUSTOM_TOOL(PARSE_JSON(?))`,
      { binds: [JSON.stringify(spec)] }
    )

    const result = rows[0] as Record<string, unknown> | undefined
    const firstValue = result ? Object.values(result)[0] : null

    let parsed: Record<string, unknown> = {}
    if (typeof firstValue === "string") {
      try { parsed = JSON.parse(firstValue) } catch { parsed = { result: firstValue } }
    } else if (typeof firstValue === "object" && firstValue !== null) {
      parsed = firstValue as Record<string, unknown>
    }

    if (parsed.status === "ERROR") {
      return Response.json({ error: parsed.error }, { status: 400 })
    }

    return Response.json(parsed)
  } catch (e) {
    console.error(new Date().toISOString(), "[tool onboard error]", e)
    return safeErrorResponse("Tool onboarding failed", 500)
  }
}
