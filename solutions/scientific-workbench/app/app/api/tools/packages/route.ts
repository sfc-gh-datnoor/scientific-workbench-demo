import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"

export const dynamic = "force-dynamic"

export async function GET(req: NextRequest) {
  try {
    const pkg = req.nextUrl.searchParams.get("package")
    if (!pkg) {
      return safeErrorResponse("package parameter is required", 400)
    }

    const rows = await querySnowflake(
      `SELECT capability_name, display_name, description, domains
       FROM SCIENTIFIC_WORKBENCH.CATALOG.BYOT_PACKAGE_CATALOG
       WHERE package_name = ?
       ORDER BY capability_name`,
      { binds: [pkg.toLowerCase()] }
    )

    return Response.json({
      package: pkg,
      capabilities: rows.map((r: Record<string, unknown>) => ({
        capability_name: r.CAPABILITY_NAME,
        display_name: r.DISPLAY_NAME,
        description: r.DESCRIPTION,
        domains: r.DOMAINS,
      })),
    })
  } catch (e) {
    console.error(new Date().toISOString(), "[packages lookup error]", e)
    return safeErrorResponse("Package lookup failed", 500)
  }
}
