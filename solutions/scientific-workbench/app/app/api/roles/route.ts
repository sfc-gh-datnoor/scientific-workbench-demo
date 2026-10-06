import { querySnowflake } from "@/lib/snowflake"
import { quoteIdentifier, safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

const RoleSchema = z.object({
  role: z.string().min(1).max(256),
})

async function fetchAvailableRoles(): Promise<string[]> {
  try {
    const rows = await querySnowflake(
      `SELECT value::VARCHAR AS role FROM TABLE(FLATTEN(
        input => PARSE_JSON(SYSTEM$CURRENT_USER_ROLES('ALL'))
      )) ORDER BY role`
    )
    return rows.map((r) => String(r.ROLE))
  } catch {
    try {
      const rows = await querySnowflake("SELECT CURRENT_ROLE() AS role")
      return [String(rows[0]?.ROLE ?? "PUBLIC")]
    } catch {
      return ["PUBLIC"]
    }
  }
}

export async function GET() {
  try {
    const [currentRow] = await querySnowflake("SELECT CURRENT_ROLE() AS role, CURRENT_USER() AS username")
    const roles = await fetchAvailableRoles()
    return Response.json({
      current_role: currentRow?.ROLE ?? "UNKNOWN",
      username: currentRow?.USERNAME ?? "UNKNOWN",
      available_roles: roles,
    })
  } catch (e) {
    console.error("Roles GET error:", e)
    return safeErrorResponse("Failed to fetch roles", 500)
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = RoleSchema.safeParse(await req.json())
    if (!body.success) {
      return safeErrorResponse("Invalid request: role is required", 400)
    }
    const { role } = body.data

    // Validate role against the user's available roles (case-insensitive allowlist)
    const availableRoles = await fetchAvailableRoles()
    const normalized = role.toUpperCase()
    if (!availableRoles.some((r) => r.toUpperCase() === normalized)) {
      return safeErrorResponse("Role not accessible", 403)
    }

    // USE ROLE does not support bind variables, but the role is validated
    // against the user's own role list so it's safe to interpolate.
    // Use caller's rights so the role switch only affects the caller's
    // session, not the shared owner connection pool.
    const quotedRole = quoteIdentifier(normalized)
    await querySnowflake(`USE ROLE ${quotedRole}`, { callersRights: true })
    const [row] = await querySnowflake("SELECT CURRENT_ROLE() AS role", { callersRights: true })
    return Response.json({ success: true, active_role: row?.ROLE ?? role })
  } catch (e) {
    console.error("Roles POST error:", e)
    return safeErrorResponse("Cannot switch to the requested role", 403)
  }
}
