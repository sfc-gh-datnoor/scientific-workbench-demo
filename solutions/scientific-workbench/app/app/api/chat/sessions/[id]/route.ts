import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params

    // Load thread messages from the Cortex Agent thread
    // THREAD_MESSAGES requires a numeric literal, not a bind variable
    if (!/^\d+$/.test(id)) {
      return Response.json({ messages: [] })
    }
    const rows = await querySnowflake(
      `SELECT SNOWFLAKE.CORTEX.THREAD_MESSAGES(${id}) AS thread_data`
    )

    if (rows.length === 0) {
      return Response.json({ messages: [] })
    }

    const raw = (rows[0] as { THREAD_DATA: unknown })?.THREAD_DATA
    let threadData: Record<string, unknown> = {}
    if (typeof raw === "string") {
      try { threadData = JSON.parse(raw) } catch { /* empty */ }
    } else if (raw && typeof raw === "object") {
      threadData = raw as Record<string, unknown>
    }

    // Extract messages from thread data
    const rawMessages = (threadData.messages || []) as Array<{
      role: string
      message_id?: string | number
      message_payload: string
      created_on: number
    }>

    const messages = rawMessages.map((m) => {
      let content = ""
      try {
        const payload = typeof m.message_payload === "string" ? JSON.parse(m.message_payload) : m.message_payload
        if (payload && typeof payload === "object") {
          const p = payload as Record<string, unknown>
          if (Array.isArray(p.content)) {
            content = (p.content as Array<{ type: string; text?: string }>)
              .filter((c) => c.type === "text")
              .map((c) => c.text ?? "")
              .join("\n")
          } else if (typeof p.content === "string") {
            content = p.content
          } else if (typeof p.text === "string") {
            content = p.text
          }
        }
      } catch {
        content = String(m.message_payload || "")
      }

      return {
        role: m.role === "assistant" ? "agent" : m.role,
        content,
        message_id: m.message_id ? String(m.message_id) : null,
        timestamp: m.created_on ? new Date(m.created_on).toISOString() : new Date().toISOString(),
      }
    }).filter((m) => m.content.trim().length > 0)
      .sort((a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime())

    // Find the last assistant message_id for thread continuation
    const lastAssistantMsg = [...messages].reverse().find((m) => m.role === "agent" && m.message_id)
    const lastAssistantMessageId = lastAssistantMsg?.message_id ?? null

    return Response.json({ messages, last_assistant_message_id: lastAssistantMessageId })
  } catch (e) {
    console.error("[chat session GET]", e)
    return Response.json({ messages: [] })
  }
}

const UpdateSchema = z.object({
  title: z.string().max(200).optional(),
})

export async function PUT(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params
    const body = UpdateSchema.safeParse(await req.json())
    if (!body.success) return safeErrorResponse("Invalid request", 400)

    if (body.data.title) {
      await querySnowflake(
        `UPDATE SCIENTIFIC_WORKBENCH.CATALOG.CHAT_SESSIONS
         SET TITLE = ?, UPDATED_AT = CURRENT_TIMESTAMP()
         WHERE SESSION_ID = ? AND USER_NAME = CURRENT_USER()`,
        { binds: [body.data.title, id] }
      )
    } else {
      await querySnowflake(
        `UPDATE SCIENTIFIC_WORKBENCH.CATALOG.CHAT_SESSIONS
         SET UPDATED_AT = CURRENT_TIMESTAMP()
         WHERE SESSION_ID = ? AND USER_NAME = CURRENT_USER()`,
        { binds: [id] }
      )
    }

    return Response.json({ success: true })
  } catch (e) {
    console.error("[chat session PUT]", e)
    return safeErrorResponse("Failed to update session", 500)
  }
}

export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params
    await querySnowflake(
      `DELETE FROM SCIENTIFIC_WORKBENCH.CATALOG.CHAT_SESSIONS WHERE SESSION_ID = ? AND USER_NAME = CURRENT_USER()`,
      { binds: [id] }
    )
    return Response.json({ success: true })
  } catch (e) {
    console.error("[chat session DELETE]", e)
    return safeErrorResponse("Failed to delete session", 500)
  }
}
