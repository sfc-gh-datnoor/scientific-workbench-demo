import { querySnowflakeLongRunning } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

const AGENT_NAME = "SCIENTIFIC_WORKBENCH.CATALOG.DISCOVERY_AGENT"

const RequestSchema = z.object({
  message: z.string().min(1).max(50000),
  thread_id: z.string().max(256).nullish(),
  parent_message_id: z.string().max(256).nullish(),
})

export async function POST(req: NextRequest) {
  try {
    const body = RequestSchema.safeParse(await req.json())
    if (!body.success) {
      return safeErrorResponse("Invalid request: " + body.error.issues[0]?.message, 400)
    }
    const { message, thread_id, parent_message_id } = body.data

    // Build the messages JSON — include thread_id and parent_message_id
    // in the body for thread continuity (not as the 3rd SQL argument)
    const payload: Record<string, unknown> = {
      messages: [
        { role: "user", content: [{ type: "text", text: message }] },
      ],
    }
    if (thread_id && thread_id !== "null") payload.thread_id = thread_id
    if (parent_message_id && parent_message_id !== "null") payload.parent_message_id = parent_message_id

    const agentSql = `SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(?, ?, TRUE) AS resp`

    const rows = await querySnowflakeLongRunning(agentSql, {
      binds: [AGENT_NAME, JSON.stringify(payload)],
    })
    const raw = (rows[0] as { RESP: unknown })?.RESP

    let parsed: unknown = raw
    if (typeof raw === "string") {
      try { parsed = JSON.parse(raw) } catch { parsed = raw }
    }

    let responseText = ""
    if (parsed && typeof parsed === "object") {
      responseText = extractText(parsed)
    } else if (typeof parsed === "string") {
      responseText = parsed
    }
    if (!responseText && raw) {
      responseText = typeof raw === "string" ? raw : JSON.stringify(raw)
    }

    // Extract thread_id and assistant_message_id from metadata
    let responseThreadId: string | null = null
    let assistantMessageId: string | null = null
    if (parsed && typeof parsed === "object") {
      const meta = (parsed as Record<string, unknown>).metadata as Record<string, unknown> | undefined
      if (meta?.thread_id) responseThreadId = String(meta.thread_id)
      if (meta?.assistant_message_id) assistantMessageId = String(meta.assistant_message_id)
    }

    return Response.json({
      response: responseText,
      thread_id: responseThreadId,
      parent_message_id: assistantMessageId,
    })
  } catch (e) {
    console.error(new Date().toISOString(), "[agent API error]", e)
    return safeErrorResponse("Agent invocation failed", 500)
  }
}

function extractText(resp: unknown): string {
  if (!resp || typeof resp !== "object") return String(resp ?? "")
  const r = resp as Record<string, unknown>
  if (typeof r.text === "string") return r.text
  if (typeof r.content === "string") return r.content
  if (Array.isArray(r.content)) {
    return (r.content as Array<{ type: string; text?: string }>)
      .filter((c) => c.type === "text")
      .map((c) => c.text ?? "")
      .join("\n")
  }
  return JSON.stringify(resp)
}
