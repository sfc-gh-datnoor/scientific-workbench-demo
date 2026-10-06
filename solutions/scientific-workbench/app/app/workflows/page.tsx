import { querySnowflake } from "@/lib/snowflake"
import { WorkflowsClient } from "./WorkflowsClient"

export const dynamic = "force-dynamic"
export const metadata = { title: "Workflows — Scientific Workbench" }

async function getTemplates() {
  try {
    return await querySnowflake(`
      SELECT TEMPLATE_ID, NAME, DISPLAY_NAME, DESCRIPTION, PERSONA,
             STEPS::VARCHAR AS STEPS, VERSION, STATUS
      FROM SCIENTIFIC_WORKBENCH.WORKFLOWS.TEMPLATES
      WHERE STATUS = 'active'
      ORDER BY NAME
    `)
  } catch { return [] }
}

async function getPipelineTools() {
  try {
    return await querySnowflake(`
      SELECT TOOL_ID, NAME, TOOL_TYPE AS TYPE,
             DOMAIN[0]::VARCHAR AS DOMAIN,
             COMPUTE_ENV AS COMPUTE_TYPE,
             NULL AS ESTIMATED_RUNTIME, DESCRIPTION
      FROM SCIENTIFIC_WORKBENCH.CATALOG.TOOLS
      WHERE TOOL_TYPE = 'pipeline' AND STATUS = 'active'
      ORDER BY NAME
    `)
  } catch { return [] }
}

export default async function WorkflowsPage() {
  const [templates, pipelineTools] = await Promise.all([getTemplates(), getPipelineTools()])
  return <WorkflowsClient
    templates={templates as { TEMPLATE_ID: string; NAME: string; DISPLAY_NAME: string; DESCRIPTION: string; PERSONA: string; STEPS: string; VERSION: string; STATUS: string }[]}
    pipelineTools={pipelineTools as { TOOL_ID: string; NAME: string; TYPE: string; DOMAIN: string; COMPUTE_TYPE: string; ESTIMATED_RUNTIME: string; DESCRIPTION: string }[]}
  />
}
