import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

export async function GET() {
  try {
    const rows = await querySnowflake(
      `SELECT SESSION_ID, TITLE, UPDATED_AT
       FROM SCIENTIFIC_WORKBENCH.CATALOG.CHAT_SESSIONS
       ORDER BY UPDATED_AT DESC
       LIMIT 50`
    )
    return Response.json({ sessions: rows })
  } catch (e) {
    console.error("[chat sessions GET]", e)
    return safeErrorResponse("Failed to load sessions", 500)
  }
}

const CreateSchema = z.object({
  title: z.string().max(200).optional(),
  thread_id: z.string().max(256),
})

export async function POST(req: NextRequest) {
  try {
    const body = CreateSchema.safeParse(await req.json())
    if (!body.success) {
      return safeErrorResponse("Invalid request", 400)
    }
    const { title, thread_id } = body.data

    await querySnowflake(
      `INSERT INTO SCIENTIFIC_WORKBENCH.CATALOG.CHAT_SESSIONS
       (SESSION_ID, TITLE, MESSAGES, USER_NAME, CREATED_AT, UPDATED_AT)
       SELECT ?, ?, PARSE_JSON('[]'), CURRENT_USER(), CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()`,
      { binds: [thread_id, title || "New conversation"] }
    )

    return Response.json({ session_id: thread_id, title })
  } catch (e) {
    console.error("[chat sessions POST]", e)
    return safeErrorResponse("Failed to create session", 500)
  }
}
