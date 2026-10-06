"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { ArrowLeft, ArrowRight, Check, Loader2, AlertTriangle } from "lucide-react"

type SourceType = "rest_api" | "python_code" | "python_package" | "git_repo" | "existing_procedure" | "spcs_container"
type ComputeEnv = "warehouse" | "gpu_nim" | "spcs_container"
type Visibility = "personal" | "shared"

interface Parameter {
  name: string
  type: string
  description: string
  required: boolean
}

interface ToolSpec {
  name: string
  display_name: string
  description: string
  domains: string[]
  source_type: SourceType
  source_config: Record<string, unknown>
  parameters: Record<string, { type: string; description: string; required?: boolean }>
  return_type: string
  compute_env: ComputeEnv
  visibility: Visibility
  example_usage: string
}

const DOMAIN_OPTIONS = [
  "genomics", "chemistry", "drug-discovery", "structural-biology",
  "proteomics", "bioinformatics", "clinical", "custom",
]

const ALLOWED_PACKAGES = [
  "pandas", "numpy", "scipy", "scikit-learn", "requests", "rdkit", "biopython",
]

const PARAM_TYPES = ["STRING", "INT", "FLOAT", "BOOLEAN", "VARIANT"]

export default function OnboardPage() {
  const router = useRouter()
  const [step, setStep] = useState(0)
  const [loading, setLoading] = useState(false)
  const [validating, setValidating] = useState(false)
  const [validationResult, setValidationResult] = useState<{ valid: boolean; errors: string[] } | null>(null)
  const [submitResult, setSubmitResult] = useState<Record<string, unknown> | null>(null)
  const [error, setError] = useState("")

  // Step 1: Identity
  const [name, setName] = useState("")
  const [displayName, setDisplayName] = useState("")
  const [description, setDescription] = useState("")
  const [domains, setDomains] = useState<string[]>(["custom"])

  // Step 2: Source
  const [sourceType, setSourceType] = useState<SourceType>("rest_api")
  // REST API
  const [apiUrl, setApiUrl] = useState("")
  const [apiMethod, setApiMethod] = useState("POST")
  const [authType, setAuthType] = useState("none")
  const [responsePath, setResponsePath] = useState("")
  // Python Code
  const [code, setCode] = useState("")
  const [packages, setPackages] = useState<string[]>([])
  // Existing Procedure
  const [functionReference, setFunctionReference] = useState("")
  // SPCS Container
  const [imageUri, setImageUri] = useState("")
  const [endpointPath, setEndpointPath] = useState("/predict")
  const [port, setPort] = useState(8080)
  const [computePool, setComputePool] = useState("WORKBENCH_CPU_POOL")
  // Python Package
  const [packageName, setPackageName] = useState("")
  const [capabilityName, setCapabilityName] = useState("")
  const [capabilityDesc, setCapabilityDesc] = useState("")
  const [catalogCapabilities, setCatalogCapabilities] = useState<{ capability_name: string; display_name: string; description: string }[]>([])
  const [loadingCapabilities, setLoadingCapabilities] = useState(false)
  // Git Repo
  const [repoUrl, setRepoUrl] = useState("")
  const [repoEntryPoint, setRepoEntryPoint] = useState("")
  const [repoCode, setRepoCode] = useState("")
  const [repoPackages, setRepoPackages] = useState<string[]>([])

  // Step 3: Configuration
  const [params, setParams] = useState<Parameter[]>([
    { name: "output_table", type: "STRING", description: "Result table name", required: true },
  ])
  const [computeEnv, setComputeEnv] = useState<ComputeEnv>("warehouse")
  const [visibility, setVisibility] = useState<Visibility>("shared")

  const steps = ["Identity", "Source", "Configuration", "Review"]

  function buildSpec(): ToolSpec {
    const sourceConfig: Record<string, unknown> = { display_name: displayName }
    if (sourceType === "rest_api") {
      sourceConfig.url = apiUrl
      sourceConfig.method = apiMethod
      sourceConfig.auth_type = authType
      sourceConfig.response_path = responsePath
    } else if (sourceType === "python_code") {
      sourceConfig.code = code
      sourceConfig.packages = packages
    } else if (sourceType === "existing_procedure") {
      sourceConfig.function_reference = functionReference
    } else if (sourceType === "spcs_container") {
      sourceConfig.image_uri = imageUri
      sourceConfig.endpoint_path = endpointPath
      sourceConfig.port = port
      sourceConfig.compute_pool = computePool
    } else if (sourceType === "python_package") {
      sourceConfig.package_name = packageName
      sourceConfig.capability_name = capabilityName
      sourceConfig.capability_description = capabilityDesc
    } else if (sourceType === "git_repo") {
      sourceConfig.repo_url = repoUrl
      sourceConfig.entry_point = repoEntryPoint
      sourceConfig.code = repoCode
      sourceConfig.packages = repoPackages
    }

    const paramObj: Record<string, { type: string; description: string; required?: boolean }> = {}
    for (const p of params) {
      paramObj[p.name] = { type: p.type, description: p.description, required: p.required }
    }

    return {
      name,
      display_name: displayName || name,
      description,
      domains,
      source_type: sourceType,
      source_config: sourceConfig,
      parameters: paramObj,
      return_type: "VARCHAR",
      compute_env: computeEnv,
      visibility,
      example_usage: "",
    }
  }

  async function handleValidate() {
    setValidating(true)
    setValidationResult(null)
    setError("")
    try {
      const res = await fetch("/api/tools/onboard/validate", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(buildSpec()),
      })
      if (!res.ok) {
        const text = await res.text()
        try { setValidationResult(JSON.parse(text)) } catch { setValidationResult({ valid: false, errors: [text || `Server error (${res.status})`] }) }
      } else {
        const data = await res.json()
        setValidationResult(data)
      }
    } catch {
      setValidationResult({ valid: false, errors: ["Validation request failed"] })
    }
    setValidating(false)
  }

  async function handleSubmit() {
    setLoading(true)
    setError("")
    setSubmitResult(null)
    try {
      const res = await fetch("/api/tools/onboard", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(buildSpec()),
      })
      const text = await res.text()
      let data: Record<string, unknown>
      try { data = JSON.parse(text) } catch { data = { error: text || `Server error (${res.status})` } }
      if (!res.ok || data.error) {
        setError(String(data.error || data.message || `Submission failed (${res.status})`))
      } else {
        setSubmitResult(data)
      }
    } catch (e) {
      setError(`Submission failed: ${e instanceof Error ? e.message : "Unknown error"}`)
    }
    setLoading(false)
  }

  function addParam() {
    setParams([...params, { name: "", type: "STRING", description: "", required: false }])
  }

  function removeParam(idx: number) {
    if (params[idx].name === "output_table") return
    setParams(params.filter((_, i) => i !== idx))
  }

  function updateParam(idx: number, field: keyof Parameter, value: string | boolean) {
    const updated = [...params]
    ;(updated[idx] as unknown as Record<string, unknown>)[field] = value
    setParams(updated)
  }

  const inputStyle: React.CSSProperties = {
    width: "100%", padding: "8px 12px", fontSize: 13, borderRadius: "var(--radius-sm)",
    border: "1px solid var(--sf-border)", background: "var(--sf-surface-1)",
    color: "var(--sf-text)", outline: "none",
  }

  const labelStyle: React.CSSProperties = {
    fontSize: 12, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4,
    display: "block", textTransform: "uppercase" as const, letterSpacing: "0.04em",
  }

  const btnPrimary: React.CSSProperties = {
    padding: "8px 20px", fontSize: 13, fontWeight: 500, borderRadius: "var(--radius-sm)",
    border: "none", background: "var(--sf-blue)", color: "#fff", cursor: "pointer",
    display: "inline-flex", alignItems: "center", gap: 6,
  }

  const btnSecondary: React.CSSProperties = {
    ...btnPrimary, background: "var(--sf-surface-2)", color: "var(--sf-text)",
    border: "1px solid var(--sf-border)",
  }

  return (
    <div style={{ maxWidth: 720, margin: "0 auto" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 24 }}>
        <button onClick={() => router.push("/tools")} style={{ background: "none", border: "none", cursor: "pointer", color: "var(--sf-text-muted)", display: "flex" }}>
          <ArrowLeft size={18} />
        </button>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)", margin: 0 }}>Add Custom Tool</h1>
      </div>

      {/* Step indicator */}
      <div style={{ display: "flex", gap: 0, marginBottom: 32 }}>
        {steps.map((s, i) => (
          <div key={s} style={{ flex: 1, textAlign: "center" }}>
            <div style={{
              width: 28, height: 28, borderRadius: "50%", margin: "0 auto 6px",
              display: "flex", alignItems: "center", justifyContent: "center", fontSize: 12, fontWeight: 600,
              background: i <= step ? "var(--sf-blue)" : "var(--sf-surface-2)",
              color: i <= step ? "#fff" : "var(--sf-text-muted)",
            }}>
              {i < step ? <Check size={14} /> : i + 1}
            </div>
            <div style={{ fontSize: 11, color: i <= step ? "var(--sf-text)" : "var(--sf-text-muted)" }}>{s}</div>
          </div>
        ))}
      </div>

      {/* Step 1: Identity */}
      {step === 0 && (
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div>
            <label style={labelStyle}>Tool Name</label>
            <input style={inputStyle} value={name} onChange={e => setName(e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, "_"))}
              placeholder="e.g. blast_search" />
            <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 4 }}>Lowercase, underscores only. This is the programmatic identifier.</div>
          </div>
          <div>
            <label style={labelStyle}>Display Name</label>
            <input style={inputStyle} value={displayName} onChange={e => setDisplayName(e.target.value)} placeholder="e.g. BLAST Sequence Search" />
          </div>
          <div>
            <label style={labelStyle}>Description</label>
            <textarea style={{ ...inputStyle, minHeight: 80, resize: "vertical" }} value={description} onChange={e => setDescription(e.target.value)}
              placeholder="What does this tool do? Be specific about inputs and outputs." />
          </div>
          <div>
            <label style={labelStyle}>Domains</label>
            <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
              {DOMAIN_OPTIONS.map(d => (
                <button key={d} onClick={() => setDomains(domains.includes(d) ? domains.filter(x => x !== d) : [...domains, d])}
                  style={{
                    fontSize: 12, padding: "4px 12px", borderRadius: 20, cursor: "pointer",
                    border: `1px solid ${domains.includes(d) ? "var(--sf-blue)" : "var(--sf-border)"}`,
                    background: domains.includes(d) ? "var(--role-info-bg)" : "var(--sf-surface-1)",
                    color: domains.includes(d) ? "var(--sf-blue)" : "var(--sf-text-muted)",
                  }}>
                  {d}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Step 2: Source */}
      {step === 1 && (
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div>
            <label style={labelStyle}>Source Type</label>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
              {([
                ["python_package", "Python Package", "Install from a known library (RDKit, BioPython, etc.)"],
                ["rest_api", "REST API", "Wrap an external HTTP endpoint"],
                ["python_code", "Python Code", "Custom Python function (sandboxed)"],
                ["git_repo", "Git Repository", "Import a tool from a Git repo"],
                ["existing_procedure", "Existing Procedure", "Already in Snowflake"],
                ["spcs_container", "SPCS Container", "Docker image on Snowflake"],
              ] as [SourceType, string, string][]).map(([val, label, desc]) => (
                <div key={val} onClick={() => setSourceType(val)}
                  style={{
                    padding: 12, borderRadius: "var(--radius-sm)", cursor: "pointer",
                    border: `1.5px solid ${sourceType === val ? "var(--sf-blue)" : "var(--sf-border)"}`,
                    background: sourceType === val ? "var(--role-info-bg)" : "var(--sf-surface-1)",
                  }}>
                  <div style={{ fontSize: 13, fontWeight: 500, color: "var(--sf-text)" }}>{label}</div>
                  <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 2 }}>{desc}</div>
                </div>
              ))}
            </div>
          </div>

          {sourceType === "rest_api" && (
            <>
              <div>
                <label style={labelStyle}>API URL (HTTPS only)</label>
                <input style={inputStyle} value={apiUrl} onChange={e => setApiUrl(e.target.value)} placeholder="https://api.example.com/v1/predict" />
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
                <div>
                  <label style={labelStyle}>Method</label>
                  <select style={inputStyle} value={apiMethod} onChange={e => setApiMethod(e.target.value)}>
                    <option value="POST">POST</option>
                    <option value="GET">GET</option>
                  </select>
                </div>
                <div>
                  <label style={labelStyle}>Authentication</label>
                  <select style={inputStyle} value={authType} onChange={e => setAuthType(e.target.value)}>
                    <option value="none">None</option>
                    <option value="api_key">API Key (header)</option>
                    <option value="bearer">Bearer Token</option>
                  </select>
                </div>
              </div>
              <div>
                <label style={labelStyle}>Response JSON Path (optional)</label>
                <input style={inputStyle} value={responsePath} onChange={e => setResponsePath(e.target.value)} placeholder="e.g. data.results" />
                <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 4 }}>Dot-separated path to extract results from the response JSON.</div>
              </div>
              {authType !== "none" && (
                <div style={{ padding: 12, borderRadius: "var(--radius-sm)", background: "#fef3cd", border: "1px solid #ffc107", fontSize: 12, color: "#856404" }}>
                  <AlertTriangle size={14} style={{ display: "inline", marginRight: 6, verticalAlign: "middle" }} />
                  After approval, an admin will need to create a secret: SCIENTIFIC_WORKBENCH.CATALOG.CUSTOM_TOOL_{name.toUpperCase()}_KEY and add the API domain to the allowed list.
                </div>
              )}
            </>
          )}

          {sourceType === "python_code" && (
            <>
              <div>
                <label style={labelStyle}>Python Code</label>
                <textarea style={{ ...inputStyle, fontFamily: "var(--font-fira-mono)", minHeight: 200, resize: "vertical", fontSize: 12, lineHeight: 1.6 }}
                  value={code} onChange={e => setCode(e.target.value)}
                  placeholder={"# Your function body. Receives parameters as arguments.\n# Return a value, dict, or pandas DataFrame.\n\nimport pandas as pd\n\n# Example:\nresult = pd.DataFrame({'col': [1, 2, 3]})\nreturn result"} />
                <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 4 }}>
                  Code runs in Snowpark Python 3.10. No os, subprocess, socket, eval, or exec allowed.
                </div>
              </div>
              <div>
                <label style={labelStyle}>Additional Packages</label>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
                  {ALLOWED_PACKAGES.map(pkg => (
                    <button key={pkg} onClick={() => setPackages(packages.includes(pkg) ? packages.filter(p => p !== pkg) : [...packages, pkg])}
                      style={{
                        fontSize: 12, padding: "4px 10px", borderRadius: 20, cursor: "pointer", fontFamily: "var(--font-fira-mono)",
                        border: `1px solid ${packages.includes(pkg) ? "var(--sf-blue)" : "var(--sf-border)"}`,
                        background: packages.includes(pkg) ? "var(--role-info-bg)" : "var(--sf-surface-1)",
                        color: packages.includes(pkg) ? "var(--sf-blue)" : "var(--sf-text-muted)",
                      }}>
                      {pkg}
                    </button>
                  ))}
                </div>
              </div>
            </>
          )}

          {sourceType === "existing_procedure" && (
            <div>
              <label style={labelStyle}>Fully Qualified Procedure Name</label>
              <input style={{ ...inputStyle, fontFamily: "var(--font-fira-mono)" }} value={functionReference} onChange={e => setFunctionReference(e.target.value)}
                placeholder="DATABASE.SCHEMA.PROCEDURE_NAME" />
              <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 4 }}>
                The procedure must already exist. Parameters will be auto-extracted from its signature.
              </div>
            </div>
          )}

          {sourceType === "spcs_container" && (
            <>
              <div>
                <label style={labelStyle}>Image URI (Snowflake Image Repo)</label>
                <input style={inputStyle} value={imageUri} onChange={e => setImageUri(e.target.value)}
                  placeholder="/SCIENTIFIC_WORKBENCH/CATALOG/IMAGES/my-tool:latest" />
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12 }}>
                <div>
                  <label style={labelStyle}>Endpoint Path</label>
                  <input style={inputStyle} value={endpointPath} onChange={e => setEndpointPath(e.target.value)} />
                </div>
                <div>
                  <label style={labelStyle}>Port</label>
                  <input style={inputStyle} type="number" value={port} onChange={e => setPort(parseInt(e.target.value) || 8080)} />
                </div>
                <div>
                  <label style={labelStyle}>Compute Pool</label>
                  <select style={inputStyle} value={computePool} onChange={e => setComputePool(e.target.value)}>
                    <option value="WORKBENCH_CPU_POOL">CPU Pool</option>
                    <option value="NIM_GPU_A10G_POOL">GPU A10G (24 GB)</option>
                    <option value="NIM_GPU_L40S_POOL">GPU L40S (48 GB)</option>
                  </select>
                </div>
              </div>
            </>
          )}

          {sourceType === "python_package" && (
            <>
              <div>
                <label style={labelStyle}>Package Name</label>
                <select style={inputStyle} value={packageName} onChange={async e => {
                  const pkg = e.target.value
                  setPackageName(pkg)
                  setCapabilityName("")
                  setCapabilityDesc("")
                  if (pkg) {
                    setLoadingCapabilities(true)
                    try {
                      const res = await fetch(`/api/tools/packages?package=${encodeURIComponent(pkg)}`)
                      const data = await res.json()
                      setCatalogCapabilities(data.capabilities || [])
                    } catch { setCatalogCapabilities([]) }
                    setLoadingCapabilities(false)
                  } else {
                    setCatalogCapabilities([])
                  }
                }}>
                  <option value="">Select a package...</option>
                  <option value="rdkit">RDKit (Cheminformatics)</option>
                  <option value="biopython">BioPython (Bioinformatics)</option>
                  <option value="scikit-learn">scikit-learn (Machine Learning)</option>
                </select>
              </div>

              {packageName && (
                <div>
                  <label style={labelStyle}>Capability</label>
                  {loadingCapabilities ? (
                    <div style={{ fontSize: 12, color: "var(--sf-text-muted)", padding: 8 }}>Loading capabilities...</div>
                  ) : catalogCapabilities.length > 0 ? (
                    <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                      {catalogCapabilities.map(cap => (
                        <div key={cap.capability_name}
                          onClick={() => { setCapabilityName(cap.capability_name); setCapabilityDesc("") }}
                          style={{
                            padding: 10, borderRadius: "var(--radius-sm)", cursor: "pointer",
                            border: `1.5px solid ${capabilityName === cap.capability_name ? "var(--sf-blue)" : "var(--sf-border)"}`,
                            background: capabilityName === cap.capability_name ? "var(--role-info-bg)" : "var(--sf-surface-1)",
                          }}>
                          <div style={{ fontSize: 13, fontWeight: 500, color: "var(--sf-text)" }}>{cap.display_name}</div>
                          <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 2 }}>{cap.description}</div>
                        </div>
                      ))}
                      <div
                        onClick={() => { setCapabilityName(""); }}
                        style={{
                          padding: 10, borderRadius: "var(--radius-sm)", cursor: "pointer",
                          border: `1.5px solid ${!capabilityName ? "var(--sf-blue)" : "var(--sf-border)"}`,
                          background: !capabilityName ? "var(--role-info-bg)" : "var(--sf-surface-1)",
                        }}>
                        <div style={{ fontSize: 13, fontWeight: 500, color: "var(--sf-text)" }}>Custom Capability (AI-assisted)</div>
                        <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 2 }}>Describe what you need and AI will generate the tool code</div>
                      </div>
                    </div>
                  ) : (
                    <div style={{ fontSize: 12, color: "var(--sf-text-muted)", padding: 8 }}>
                      No pre-built capabilities found. Describe what you need below for AI-assisted generation.
                    </div>
                  )}
                </div>
              )}

              {packageName && !capabilityName && (
                <div>
                  <label style={labelStyle}>Describe the capability you need</label>
                  <textarea style={{ ...inputStyle, minHeight: 80, resize: "vertical" }} value={capabilityDesc} onChange={e => setCapabilityDesc(e.target.value)}
                    placeholder={`Describe what you want ${packageName} to do. E.g. "Calculate molecular fingerprints and cluster similar compounds"`} />
                  <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 4 }}>
                    AI will generate the tool code based on your description. The generated code will be reviewed before activation.
                  </div>
                </div>
              )}
            </>
          )}

          {sourceType === "git_repo" && (
            <>
              <div>
                <label style={labelStyle}>Repository URL</label>
                <input style={inputStyle} value={repoUrl} onChange={e => setRepoUrl(e.target.value)}
                  placeholder="https://github.com/org/tool-repo" />
              </div>
              <div>
                <label style={labelStyle}>Entry Point (optional)</label>
                <input style={inputStyle} value={repoEntryPoint} onChange={e => setRepoEntryPoint(e.target.value)}
                  placeholder="src/main.py or tool.json" />
                <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 4 }}>
                  Path to the main script or tool manifest in the repo.
                </div>
              </div>
              <div>
                <label style={labelStyle}>Tool Code (paste from repo)</label>
                <textarea style={{ ...inputStyle, fontFamily: "var(--font-fira-mono)", minHeight: 160, resize: "vertical", fontSize: 12, lineHeight: 1.6 }}
                  value={repoCode} onChange={e => setRepoCode(e.target.value)}
                  placeholder="# Paste the relevant Python code from the repository here" />
                <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 4 }}>
                  Currently, code must be pasted manually. Direct repo import is planned for a future release.
                </div>
              </div>
              <div>
                <label style={labelStyle}>Required Packages</label>
                <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
                  {ALLOWED_PACKAGES.map(pkg => (
                    <button key={pkg} onClick={() => setRepoPackages(repoPackages.includes(pkg) ? repoPackages.filter(p => p !== pkg) : [...repoPackages, pkg])}
                      style={{
                        fontSize: 12, padding: "4px 10px", borderRadius: 20, cursor: "pointer", fontFamily: "var(--font-fira-mono)",
                        border: `1px solid ${repoPackages.includes(pkg) ? "var(--sf-blue)" : "var(--sf-border)"}`,
                        background: repoPackages.includes(pkg) ? "var(--role-info-bg)" : "var(--sf-surface-1)",
                        color: repoPackages.includes(pkg) ? "var(--sf-blue)" : "var(--sf-text-muted)",
                      }}>
                      {pkg}
                    </button>
                  ))}
                </div>
              </div>
            </>
          )}
        </div>
      )}

      {/* Step 3: Configuration */}
      {step === 2 && (
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          <div>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
              <label style={{ ...labelStyle, marginBottom: 0 }}>Parameters</label>
              <button onClick={addParam} style={{ ...btnSecondary, padding: "4px 12px", fontSize: 12 }}>+ Add Parameter</button>
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {params.map((p, i) => (
                <div key={i} style={{ display: "grid", gridTemplateColumns: "1fr 100px 2fr 60px 40px", gap: 8, alignItems: "center" }}>
                  <input style={{ ...inputStyle, fontFamily: "var(--font-fira-mono)", fontSize: 12 }} value={p.name}
                    onChange={e => updateParam(i, "name", e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, "_"))}
                    placeholder="param_name" disabled={p.name === "output_table"} />
                  <select style={inputStyle} value={p.type} onChange={e => updateParam(i, "type", e.target.value)} disabled={p.name === "output_table"}>
                    {PARAM_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
                  </select>
                  <input style={inputStyle} value={p.description} onChange={e => updateParam(i, "description", e.target.value)} placeholder="Description" />
                  <label style={{ fontSize: 11, display: "flex", alignItems: "center", gap: 4, cursor: "pointer", color: "var(--sf-text-muted)" }}>
                    <input type="checkbox" checked={p.required} onChange={e => updateParam(i, "required", e.target.checked)} />
                    Req
                  </label>
                  {p.name !== "output_table" && (
                    <button onClick={() => removeParam(i)} style={{ background: "none", border: "none", cursor: "pointer", color: "var(--sf-text-muted)", fontSize: 16 }}>x</button>
                  )}
                </div>
              ))}
            </div>
          </div>

          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16 }}>
            <div>
              <label style={labelStyle}>Compute Environment</label>
              <select style={inputStyle} value={computeEnv} onChange={e => setComputeEnv(e.target.value as ComputeEnv)}>
                <option value="warehouse">SQL Warehouse</option>
                <option value="gpu_nim">GPU (NIM API)</option>
                <option value="spcs_container">SPCS Container</option>
              </select>
            </div>
            <div>
              <label style={labelStyle}>Visibility</label>
              <select style={inputStyle} value={visibility} onChange={e => setVisibility(e.target.value as Visibility)}>
                <option value="personal">Personal (only you)</option>
                <option value="shared">Shared (all scientists)</option>
              </select>
            </div>
          </div>
        </div>
      )}

      {/* Step 4: Review */}
      {step === 3 && (
        <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
          {submitResult ? (
            <div style={{ padding: 20, borderRadius: "var(--radius-md)", background: "var(--role-success-bg)", border: "1px solid var(--sf-green)" }}>
              <div style={{ fontSize: 14, fontWeight: 600, color: "var(--sf-green)", marginBottom: 8 }}>
                <Check size={16} style={{ display: "inline", marginRight: 6, verticalAlign: "middle" }} />
                {submitResult.status === "active" ? "Tool Registered" : "Submitted for Approval"}
              </div>
              <div style={{ fontSize: 13, color: "var(--sf-text)" }}>
                {submitResult.status === "active"
                  ? `Tool "${name}" is now active and available in the workbench.`
                  : `Submission ${submitResult.submission_id} is pending admin review.`}
              </div>
              <button onClick={() => router.push("/tools")} style={{ ...btnPrimary, marginTop: 12 }}>Back to Tools</button>
            </div>
          ) : (
            <>
              <div style={{ padding: 16, borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", background: "var(--sf-surface-1)" }}>
                <div style={{ fontSize: 14, fontWeight: 600, color: "var(--sf-text)", marginBottom: 12 }}>Tool Summary</div>
                <div style={{ display: "grid", gridTemplateColumns: "120px 1fr", gap: "6px 12px", fontSize: 13 }}>
                  <span style={{ color: "var(--sf-text-muted)" }}>Name:</span>
                  <span style={{ fontFamily: "var(--font-fira-mono)", color: "var(--sf-text)" }}>{name}</span>
                  <span style={{ color: "var(--sf-text-muted)" }}>Display Name:</span>
                  <span style={{ color: "var(--sf-text)" }}>{displayName || name}</span>
                  <span style={{ color: "var(--sf-text-muted)" }}>Source:</span>
                  <span style={{ color: "var(--sf-text)" }}>{sourceType.replace(/_/g, " ")}</span>
                  <span style={{ color: "var(--sf-text-muted)" }}>Domains:</span>
                  <span style={{ color: "var(--sf-text)" }}>{domains.join(", ")}</span>
                  <span style={{ color: "var(--sf-text-muted)" }}>Compute:</span>
                  <span style={{ color: "var(--sf-text)" }}>{computeEnv}</span>
                  <span style={{ color: "var(--sf-text-muted)" }}>Visibility:</span>
                  <span style={{ color: "var(--sf-text)" }}>{visibility}</span>
                  <span style={{ color: "var(--sf-text-muted)" }}>Parameters:</span>
                  <span style={{ color: "var(--sf-text)" }}>{params.length}</span>
                </div>
              </div>

              {sourceType !== "existing_procedure" && (
                <div style={{ padding: 12, borderRadius: "var(--radius-sm)", background: "#e3efff", border: "1px solid var(--sf-blue)", fontSize: 12, color: "var(--sf-blue)" }}>
                  This tool requires admin approval before activation. You will be notified when it is reviewed.
                </div>
              )}

              {validationResult && (
                <div style={{
                  padding: 12, borderRadius: "var(--radius-sm)", fontSize: 12,
                  background: validationResult.valid ? "var(--role-success-bg)" : "#fef3cd",
                  border: `1px solid ${validationResult.valid ? "var(--sf-green)" : "#ffc107"}`,
                  color: validationResult.valid ? "var(--sf-green)" : "#856404",
                }}>
                  {validationResult.valid
                    ? "Validation passed. Ready to submit."
                    : `Issues: ${validationResult.errors.join("; ")}`}
                </div>
              )}

              {error && (
                <div style={{ padding: 12, borderRadius: "var(--radius-sm)", background: "#fdecea", border: "1px solid #ef5350", fontSize: 12, color: "#c62828" }}>
                  {error}
                </div>
              )}

              <div style={{ display: "flex", gap: 8 }}>
                <button onClick={handleValidate} disabled={validating} style={btnSecondary}>
                  {validating ? <><Loader2 size={14} className="animate-spin" /> Validating...</> : "Validate"}
                </button>
                <button onClick={handleSubmit} disabled={loading || !name || (validationResult !== null && validationResult.valid === false)} style={btnPrimary}>
                  {loading ? <><Loader2 size={14} className="animate-spin" /> Submitting...</> : "Submit Tool"}
                </button>
              </div>
            </>
          )}
        </div>
      )}

      {/* Navigation */}
      {!submitResult && (
        <div style={{ display: "flex", justifyContent: "space-between", marginTop: 32, paddingTop: 20, borderTop: "1px solid var(--sf-border)" }}>
          <button onClick={() => setStep(Math.max(0, step - 1))} disabled={step === 0}
            style={{ ...btnSecondary, opacity: step === 0 ? 0.4 : 1 }}>
            <ArrowLeft size={14} /> Back
          </button>
          {step < 3 ? (
            <button onClick={() => setStep(step + 1)} disabled={step === 0 && !name}
              style={{ ...btnPrimary, opacity: step === 0 && !name ? 0.4 : 1 }}>
              Next <ArrowRight size={14} />
            </button>
          ) : null}
        </div>
      )}
    </div>
  )
}
