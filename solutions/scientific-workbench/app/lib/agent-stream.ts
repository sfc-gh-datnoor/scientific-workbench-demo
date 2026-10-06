export interface AgentMetadata {
  run_id?: string
  thread_id?: number
  user_message_id?: number
  assistant_message_id?: number
  usage?: unknown
}

export interface AgentSseEvent {
  event: string
  data: Record<string, unknown>
}

export type AgentProgressKind = "tool" | "status" | "warning"

export interface AgentProgressEvent {
  id: string
  kind: AgentProgressKind
  message: string
}

export function getAgentProgressEvent(event: AgentSseEvent): Omit<AgentProgressEvent, "id"> | null {
  if (event.event === "response.tool_use") {
    const name = typeof event.data.name === "string" ? event.data.name : "scientific tool"
    return { kind: "tool", message: `Running ${name}` }
  }
  if (event.event === "response.tool_result.status") {
    const message = typeof event.data.message === "string" ? event.data.message : String(event.data.status ?? "Tool status updated")
    return { kind: "status", message }
  }
  if (event.event === "response.warning") {
    return { kind: "warning", message: String(event.data.message ?? "Agent warning") }
  }
  return null
}

export function appendAgentText(current: string, incoming: string, afterProgress = false): string {
  if (!afterProgress || current.length === 0 || /^\s/.test(incoming)) return current + incoming
  return `${current}\n\n${incoming}`
}

export function parseSseBlock(block: string): AgentSseEvent | null {
  let event = "message"
  const dataLines: string[] = []
  for (const line of block.split(/\r?\n/)) {
    if (line.startsWith("event:")) event = line.slice(6).trim()
    if (line.startsWith("data:")) dataLines.push(line.slice(5).trimStart())
  }
  if (dataLines.length === 0) return null
  try {
    return { event, data: JSON.parse(dataLines.join("\n")) as Record<string, unknown> }
  } catch {
    return null
  }
}

export function extractResponseMetadata(event: AgentSseEvent): AgentMetadata | null {
  const metadata = event.data.metadata
  if (!metadata || typeof metadata !== "object") return null
  const record = metadata as Record<string, unknown>
  if (event.event === "metadata") {
    return {
      run_id: typeof record.run_id === "string" ? record.run_id : undefined,
      user_message_id: record.role === "user" && typeof record.message_id === "number" ? record.message_id : undefined,
      assistant_message_id: record.role === "assistant" && typeof record.message_id === "number" ? record.message_id : undefined,
    }
  }
  return event.event === "response" ? record as AgentMetadata : null
}

export function mapAgentError(status: number, message: string): string {
  const normalized = message.toLowerCase()
  if (status === 400) return "VALIDATION_ERROR"
  if (status === 401 || status === 403 || normalized.includes("not authorized")) return "POLICY_DENIED"
  if (status === 404 || normalized.includes("not accessible")) return "TOOL_UNAVAILABLE"
  if (status === 408 || status === 504 || normalized.includes("timed out")) return "TIMEOUT"
  if (normalized.includes("nvidia") && normalized.includes("4")) return "UPSTREAM_INPUT_ERROR"
  if (normalized.includes("nvidia") || status >= 502) return "UPSTREAM_MODEL_ERROR"
  return "SNOWFLAKE_EXECUTION_ERROR"
}