import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

// GET — list pending/all submissions (admin only)
export async function GET() {
  try {
    const rows = await querySnowflake(
      `SELECT submission_id, tool_spec, submitted_by, submitted_at,
              status, reviewer, reviewed_at, review_notes, tool_id
       FROM SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_TOOL_SUBMISSIONS
       ORDER BY submitted_at DESC
       LIMIT 100`
    )
    return Response.json({ submissions: rows })
  } catch (e) {
    console.error(new Date().toISOString(), "[submissions list error]", e)
    return safeErrorResponse("Failed to list submissions", 500)
  }
}

const ActionSchema = z.object({
  submission_id: z.string().min(1).max(64),
  action: z.enum(["approve", "reject"]),
  notes: z.string().max(4000).optional().default(""),
})

// POST — approve or reject a submission
export async function POST(req: NextRequest) {
  try {
    const body = ActionSchema.safeParse(await req.json())
    if (!body.success) {
      return safeErrorResponse("Invalid request: " + body.error.issues[0]?.message, 400)
    }

    const { submission_id, action, notes } = body.data

    let rows: Record<string, unknown>[]
    if (action === "approve") {
      rows = await querySnowflake(
        `CALL SCIENTIFIC_WORKBENCH.CATALOG.APPROVE_CUSTOM_TOOL(?, ?)`,
        { binds: [submission_id, notes] }
      ) as Record<string, unknown>[]
    } else {
      rows = await querySnowflake(
        `CALL SCIENTIFIC_WORKBENCH.CATALOG.REJECT_CUSTOM_TOOL(?, ?)`,
        { binds: [submission_id, notes] }
      ) as Record<string, unknown>[]
    }

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
    console.error(new Date().toISOString(), "[submission action error]", e)
    return safeErrorResponse("Submission action failed", 500)
  }
}
