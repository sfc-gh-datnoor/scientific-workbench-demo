import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

const HistoryMessage = z.object({
  role: z.string(),
  content: z.string(),
})

const RequestSchema = z.object({
  tool_name: z.string().min(1).max(256),
  message: z.string().min(1).max(10000),
  history: z.array(HistoryMessage).max(50).optional(),
})

interface ToolKnowledge {
  TOOL_NAME: string
  SCIENTIFIC_CONTEXT: string
  PARAMETER_GUIDE: string
  EXAMPLE_INPUTS: { label: string; [key: string]: unknown }[]
  OUTPUT_GUIDE: string
  COMMON_PITFALLS: string
  RELATED_TOOLS: string[]
  EXAMPLE_SQL: string
}

interface Tool {
  DISPLAY_NAME: string
  DESCRIPTION: string
  PARAMETERS: string
  FUNCTION_REFERENCE: string
  TOOL_TYPE: string
}

function buildSystemPrompt(tool: Tool, knowledge: ToolKnowledge | null): string {
  const examplesText = knowledge?.EXAMPLE_INPUTS?.length
    ? knowledge.EXAMPLE_INPUTS.map((ex, i) =>
        `Example ${i + 1}: "${ex.label}"\nParameters: ${JSON.stringify(Object.fromEntries(Object.entries(ex).filter(([k]) => k !== 'label')), null, 2)}`
      ).join("\n\n")
    : "No examples available."

  return `You are the ${tool.DISPLAY_NAME} assistant. You help scientists use this tool effectively.

WHAT THIS TOOL DOES:
${knowledge?.SCIENTIFIC_CONTEXT ?? tool.DESCRIPTION}

PARAMETERS:
${knowledge?.PARAMETER_GUIDE ?? tool.PARAMETERS}

READY-TO-RUN EXAMPLES:
${examplesText}

HOW TO READ THE OUTPUT:
${knowledge?.OUTPUT_GUIDE ?? "Check the output table for results."}

COMMON PITFALLS:
${knowledge?.COMMON_PITFALLS ?? "None documented."}

EXAMPLE SQL:
${knowledge?.EXAMPLE_SQL ?? `CALL ${tool.FUNCTION_REFERENCE}(...)`}

RELATED TOOLS: ${knowledge?.RELATED_TOOLS?.join(", ") ?? "None"}

YOUR INSTRUCTIONS:
- When the user asks how to use this tool, explain with specific parameter values
- When asked for an example, pick the most relevant one from READY-TO-RUN EXAMPLES and explain each parameter
- When the user provides their inputs, validate them and show the complete CALL statement
- When the user confirms they want to execute, respond with exactly this format on its own line:
  EXECUTE:{"param_name":"value","param_name2":"value2"}
  This will auto-fill the form and run the tool.
- To suggest loading an example into the form, respond with:
  LOAD_EXAMPLE:0
  (where 0 is the example index)
- Always explain what the output columns mean after execution
- Be specific: use real SMILES, real PDB IDs, real sequences from the examples
- If the user's input looks wrong (invalid SMILES, bad PDB ID), warn them before executing`
}

export async function POST(req: NextRequest) {
  try {
    const body = RequestSchema.safeParse(await req.json())
    if (!body.success) {
      return safeErrorResponse("Invalid request: " + body.error.issues[0]?.message, 400)
    }
    const { tool_name, message, history } = body.data

    // Bind variable for tool lookup
    const tools = (await querySnowflake(
      `SELECT DISPLAY_NAME, DESCRIPTION, PARAMETERS, FUNCTION_REFERENCE, TOOL_TYPE
       FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
       WHERE NAME = ? AND STATUS = 'active' LIMIT 1`,
      { binds: [tool_name] }
    )) as Tool[]

    if (tools.length === 0) {
      return safeErrorResponse("Tool not found", 404)
    }
    const tool = tools[0]

    // Bind variable for knowledge lookup
    let knowledge: ToolKnowledge | null = null
    try {
      const kRows = (await querySnowflake(
        `SELECT * FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOL_KNOWLEDGE WHERE TOOL_NAME = ? LIMIT 1`,
        { binds: [tool_name] }
      )) as ToolKnowledge[]
      if (kRows.length > 0) knowledge = kRows[0]
    } catch {
      // Knowledge table may not exist yet
    }

    const systemPrompt = buildSystemPrompt(tool, knowledge)
    const contextParts = [systemPrompt]
    for (const h of (history ?? [])) {
      contextParts.push(`${h.role === "agent" ? "Assistant" : "User"}: ${h.content}`)
    }
    contextParts.push(`User: ${message}`)
    const fullPrompt = contextParts.join("\n\n")

    // Bind variable for the LLM prompt — no string interpolation
    const rows = await querySnowflake(
      `SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', ?) AS response`,
      { binds: [fullPrompt] }
    )
    const rawResponse = rows[0] as { RESPONSE: string } | undefined
    let responseText = ""

    if (rawResponse?.RESPONSE) {
      responseText = String(rawResponse.RESPONSE).trim()
    }

    let action: string | null = null
    let actionParams: Record<string, unknown> | null = null
    let exampleIndex: number | null = null

    const executeMatch = responseText.match(/EXECUTE:(\{[^}]+\})/)
    if (executeMatch) {
      try {
        action = "execute"
        actionParams = JSON.parse(executeMatch[1])
        responseText = responseText.replace(executeMatch[0], "").trim()
      } catch { /* ignore parse errors */ }
    }

    const exampleMatch = responseText.match(/LOAD_EXAMPLE:(\d+)/)
    if (exampleMatch) {
      action = "load_example"
      exampleIndex = parseInt(exampleMatch[1], 10)
      responseText = responseText.replace(exampleMatch[0], "").trim()
    }

    return Response.json({
      response: responseText,
      action,
      params: actionParams,
      example_index: exampleIndex,
      examples: knowledge?.EXAMPLE_INPUTS ?? [],
    })
  } catch (e) {
    console.error("[tools/agent error]", e)
    return safeErrorResponse("Tool agent failed", 500)
  }
}
