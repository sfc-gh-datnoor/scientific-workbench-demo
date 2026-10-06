import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

const RunIdSchema = z.string().min(1).max(256).regex(/^[\w-]+$/, "Invalid run_id format")

export async function GET(req: NextRequest) {
  const rawRunId = req.nextUrl.searchParams.get("run_id")
  const parsed = RunIdSchema.safeParse(rawRunId)
  if (!parsed.success) {
    return safeErrorResponse("Valid run_id is required", 400)
  }

  try {
    const rows = await querySnowflake(
      `SELECT status, current_step, agent_summary
       FROM SCIENTIFIC_WORKBENCH.WORKFLOWS.RUNS
       WHERE run_id = ?`,
      { binds: [parsed.data] }
    )
    return Response.json(rows[0] ?? {})
  } catch (e) {
    console.error("[workflow status error]", e)
    return safeErrorResponse("Status check failed", 500)
  }
}
