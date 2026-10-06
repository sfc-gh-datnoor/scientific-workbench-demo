import { querySnowflake } from "@/lib/snowflake"
import { ToolsClient } from "./ToolsClient"

export const dynamic = "force-dynamic"
export const metadata = { title: "Tools — Scientific Workbench" }

async function getTools() {
  try {
    return await querySnowflake(`
      SELECT TOOL_ID, NAME, COALESCE(TOOL_TYPE, TYPE) AS TYPE,
             DOMAIN,
             COMPUTE_TYPE,
             ESTIMATED_RUNTIME,
             DESCRIPTION,
             COALESCE(PARAMETERS, INPUT_SCHEMA) AS INPUT_SCHEMA,
             COALESCE(RETURN_TYPE, OUTPUT_SCHEMA) AS OUTPUT_SCHEMA
      FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
      WHERE STATUS = 'active'
      ORDER BY COALESCE(TOOL_TYPE, TYPE), NAME
    `)
  } catch { return [] }
}

export default async function ToolsPage() {
  const tools = await getTools()
  return <ToolsClient tools={tools as { TOOL_ID: string; NAME: string; TYPE: string; DOMAIN: string; COMPUTE_TYPE: string; ESTIMATED_RUNTIME: string; DESCRIPTION: string; INPUT_SCHEMA: string; OUTPUT_SCHEMA: string }[]} />
}
