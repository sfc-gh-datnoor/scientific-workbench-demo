import { querySnowflake } from "@/lib/snowflake"
import { safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"
import { z } from "zod"

export const dynamic = "force-dynamic"

const HistoryMessage = z.object({
  role: z.enum(["user", "assistant"]),
  content: z.string(),
})

const RequestSchema = z.object({
  message: z.string().min(1).max(10000),
  history: z.array(HistoryMessage).max(50).optional(),
})

interface Capability {
  CAPABILITY_NAME: string
  DISPLAY_NAME: string
  DESCRIPTION: string
  DOMAINS: string
  CODE_TEMPLATE: string
  PARAMETERS: Record<string, unknown> | string
}

async function queryPackageCatalog(packageName: string): Promise<Capability[]> {
  try {
    const rows = await querySnowflake(
      `SELECT capability_name, display_name, description, domains, code_template, parameters
       FROM SCIENTIFIC_WORKBENCH.CATALOG.BYOT_PACKAGE_CATALOG
       WHERE package_name = ?
       ORDER BY capability_name`,
      { binds: [packageName.toLowerCase()] }
    )
    return rows as unknown as Capability[]
  } catch {
    return []
  }
}

async function queryAllPackages(): Promise<string[]> {
  try {
    const rows = await querySnowflake(
      `SELECT DISTINCT package_name FROM SCIENTIFIC_WORKBENCH.CATALOG.BYOT_PACKAGE_CATALOG ORDER BY 1`
    )
    return (rows as { PACKAGE_NAME: string }[]).map(r => r.PACKAGE_NAME)
  } catch {
    return ["rdkit", "biopython", "scikit-learn"]
  }
}

async function queryAllowedPackages(): Promise<string[]> {
  try {
    const rows = await querySnowflake(
      `SELECT package_name FROM SCIENTIFIC_WORKBENCH.CATALOG.BYOT_PYTHON_ALLOWLIST ORDER BY 1`
    )
    return (rows as { PACKAGE_NAME: string }[]).map(r => r.PACKAGE_NAME)
  } catch {
    return ["pandas", "numpy", "scipy", "scikit-learn", "requests", "rdkit", "biopython"]
  }
}

function buildSystemPrompt(packages: string[], allowedPkgs: string[]): string {
  return `You are the Tool Onboarding Agent for a life-sciences Scientific Workbench on Snowflake. Your job is to help scientists add new tools to the platform through conversation.

YOU CAN HELP WITH THESE SOURCE TYPES:
1. Python Package — install capabilities from known packages (${packages.join(", ")})
2. REST API — wrap an external HTTPS endpoint as a callable tool
3. Python Code — custom Python function (sandboxed, allowlisted packages only)
4. Existing Procedure — register a Snowflake procedure that already exists
5. SPCS Container — a Docker image running on Snowflake container services
6. Git Repository — import tool code from a public Git repository

CURATED PACKAGES AVAILABLE: ${packages.join(", ")}
ALLOWED PYTHON PACKAGES: ${allowedPkgs.join(", ")}

YOUR CONVERSATION FLOW:
1. UNDERSTAND — Ask what the user wants to add. If they name a package, search for it.
2. SEARCH — When you identify a package name, emit SEARCH_PACKAGES:<package_name> to look up available capabilities.
3. CLARIFY — If the user wants something not in the catalog, ask about: inputs, outputs, what it does, what domain it belongs to.
4. BUILD — Construct the full tool specification including:
   - name (snake_case)
   - display_name (human readable)
   - description (what it does scientifically)
   - domains (e.g. chemistry, genomics, drug-discovery)
   - source_type
   - source_config (varies by type)
   - parameters with semantic types where applicable (SMILES_STRING, FASTA_SEQUENCE, UNIPROT_ACCESSION, PDB_ID, GENE_SYMBOL, TABLE_REFERENCE)
   - A known-answer test: one canonical input/output pair with a published reference
   - A negative test: one input the tool should reject
5. PREVIEW — Show the spec using PREVIEW_TOOL:{json} for user review
6. SUBMIT — After user confirms, emit SUBMIT_TOOL:{json} to register the tool

STRUCTURED COMMANDS (emit these on their own line):
- SEARCH_PACKAGES:<package_name> — triggers a catalog lookup, results will be provided in the next turn
- PREVIEW_TOOL:<json_spec> — renders a preview card in the UI for user review
- SUBMIT_TOOL:<json_spec> — calls the onboarding procedure to register the tool

THE TOOL SPEC FORMAT for SUBMIT_TOOL and PREVIEW_TOOL:
{
  "name": "snake_case_name",
  "display_name": "Human Readable Name",
  "description": "What it does",
  "domains": ["chemistry", "drug-discovery"],
  "source_type": "python_package|rest_api|python_code|existing_procedure|spcs_container|git_repo",
  "source_config": { ... source-specific config ... },
  "parameters": {
    "param_name": {"type": "STRING", "description": "...", "required": true, "semantic_type": "SMILES_STRING"}
  },
  "return_type": "VARCHAR",
  "compute_env": "warehouse",
  "visibility": "shared",
  "known_answer_test": {"input": {...}, "expected_output_contains": "...", "reference": "..."},
  "negative_test": {"input": {...}, "expected_error": "..."}
}

For python_package source_config: {"package_name": "rdkit", "capability_name": "molecular_descriptors"}
For rest_api source_config: {"url": "https://...", "method": "POST", "auth_type": "none|api_key|bearer", "response_path": "data.results"}
For python_code source_config: {"code": "...", "packages": ["pandas", "rdkit"]}
For existing_procedure source_config: {"function_reference": "DB.SCHEMA.PROC_NAME"}
For spcs_container source_config: {"image_uri": "...", "endpoint_path": "/predict", "port": 8080, "compute_pool": "WORKBENCH_CPU_POOL"}
For git_repo source_config: {"repo_url": "https://github.com/...", "code": "...", "packages": [...]}

RULES:
- Be concise but thorough. Scientists are busy.
- If the user says something like "add RDKit" without specifying a capability, search the catalog and present options.
- For REST APIs, always require HTTPS.
- For Python code, only allow packages from the allowlist.
- Always suggest a known-answer test based on the tool's domain.
- Show PREVIEW_TOOL before SUBMIT_TOOL — never submit without the user seeing the preview first.
- Existing procedures are auto-approved. All other types require admin approval — mention this.
- If you are unsure about something, ask rather than guess.`
}

export async function POST(req: NextRequest) {
  try {
    const body = RequestSchema.safeParse(await req.json())
    if (!body.success) {
      return safeErrorResponse("Invalid request: " + body.error.issues[0]?.message, 400)
    }
    const { message, history } = body.data

    const [packages, allowedPkgs] = await Promise.all([
      queryAllPackages(),
      queryAllowedPackages(),
    ])

    const systemPrompt = buildSystemPrompt(packages, allowedPkgs)

    // Build conversation context
    const contextParts = [systemPrompt]
    for (const h of (history ?? [])) {
      contextParts.push(`${h.role === "assistant" ? "Assistant" : "User"}: ${h.content}`)
    }
    contextParts.push(`User: ${message}`)

    let fullPrompt = contextParts.join("\n\n")

    // First pass: check if LLM wants to search packages
    const rows = await querySnowflake(
      `SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', ?) AS response`,
      { binds: [fullPrompt] }
    )
    let responseText = String((rows[0] as { RESPONSE: string })?.RESPONSE ?? "").trim()

    // Handle SEARCH_PACKAGES action — intercept, query catalog, re-prompt
    const searchMatch = responseText.match(/SEARCH_PACKAGES:(\S+)/)
    if (searchMatch) {
      const pkgName = searchMatch[1].toLowerCase().replace(/[^a-z0-9-]/g, "")
      const capabilities = await queryPackageCatalog(pkgName)

      const catalogContext = capabilities.length > 0
        ? `\n\nCATALOG RESULTS for "${pkgName}":\n${capabilities.map(c =>
            `- ${c.CAPABILITY_NAME}: ${c.DISPLAY_NAME} — ${c.DESCRIPTION} (domains: ${c.DOMAINS})`
          ).join("\n")}\n\nPresent these options to the user and ask which they want to add. If they want something not listed, offer AI-assisted generation.`
        : `\n\nNo pre-built capabilities found for "${pkgName}" in the catalog. Ask the user to describe what they want to do with ${pkgName}, and you will generate the tool specification.`

      // Re-prompt with catalog context injected
      const enrichedPrompt = fullPrompt + "\n\nAssistant: " + responseText.replace(searchMatch[0], "").trim() + catalogContext
      const rows2 = await querySnowflake(
        `SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', ?) AS response`,
        { binds: [enrichedPrompt + "\n\nAssistant:"] }
      )
      responseText = String((rows2[0] as { RESPONSE: string })?.RESPONSE ?? "").trim()
    }

    // Parse structured actions
    let action: string | null = null
    let toolSpec: Record<string, unknown> | null = null
    let submitResult: Record<string, unknown> | null = null

    // PREVIEW_TOOL
    const previewMatch = responseText.match(/PREVIEW_TOOL:(\{[\s\S]*?\})\s*$/m)
      || responseText.match(/PREVIEW_TOOL:(\{[\s\S]*\})/)
    if (previewMatch) {
      try {
        toolSpec = JSON.parse(previewMatch[1])
        action = "preview"
        responseText = responseText.replace(previewMatch[0], "").trim()
      } catch { /* ignore parse errors */ }
    }

    // SUBMIT_TOOL
    const submitMatch = responseText.match(/SUBMIT_TOOL:(\{[\s\S]*?\})\s*$/m)
      || responseText.match(/SUBMIT_TOOL:(\{[\s\S]*\})/)
    if (submitMatch) {
      try {
        const spec = JSON.parse(submitMatch[1])
        action = "submitted"
        toolSpec = spec
        responseText = responseText.replace(submitMatch[0], "").trim()

        // Actually call ONBOARD_CUSTOM_TOOL
        const onboardRows = await querySnowflake(
          `CALL SCIENTIFIC_WORKBENCH.CATALOG.ONBOARD_CUSTOM_TOOL(PARSE_JSON(?))`,
          { binds: [JSON.stringify(spec)] }
        )
        const onboardResult = onboardRows[0] as Record<string, unknown> | undefined
        const firstValue = onboardResult ? Object.values(onboardResult)[0] : null
        if (typeof firstValue === "string") {
          try { submitResult = JSON.parse(firstValue) } catch { submitResult = { result: firstValue } }
        } else if (typeof firstValue === "object" && firstValue !== null) {
          submitResult = firstValue as Record<string, unknown>
        }
      } catch (e) {
        submitResult = { status: "ERROR", error: String(e).slice(0, 500) }
      }
    }

    return Response.json({
      response: responseText,
      action,
      toolSpec,
      submitResult,
      packages,
    })
  } catch (e) {
    console.error(new Date().toISOString(), "[onboard-agent error]", e)
    return safeErrorResponse("Onboarding agent failed", 500)
  }
}
