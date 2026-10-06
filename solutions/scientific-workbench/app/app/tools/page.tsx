import { querySnowflake } from "@/lib/snowflake"
import { ToolsClient } from "./ToolsClient"

export const dynamic = "force-dynamic"
export const metadata = { title: "Tools — Scientific Workbench" }

async function getTools() {
  try {
    return await querySnowflake(`
      SELECT TOOL_ID, NAME, TOOL_TYPE AS TYPE,
             DOMAIN,
             COMPUTE_ENV AS COMPUTE_TYPE,
             NULL AS ESTIMATED_RUNTIME,
             DESCRIPTION,
             PARAMETERS AS INPUT_SCHEMA,
             RETURN_TYPE AS OUTPUT_SCHEMA
      FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
      WHERE STATUS = 'active'
      ORDER BY TOOL_TYPE, NAME
    `)
  } catch { return [] }
}

export default async function ToolsPage() {
  const tools = await getTools()
  return <ToolsClient tools={tools as { TOOL_ID: string; NAME: string; TYPE: string; DOMAIN: string; COMPUTE_TYPE: string; ESTIMATED_RUNTIME: string; DESCRIPTION: string; INPUT_SCHEMA: string; OUTPUT_SCHEMA: string }[]} />
}
