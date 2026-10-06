"use client"

import { useState, useEffect, useCallback } from "react"
import { useRouter } from "next/navigation"
import { useDetailPanel } from "@/components/detail-panel-context"
import { DetailPanelEmpty } from "@/components/detail-panel-empty"
import { GitBranch, Play, ArrowRight, Zap, X, Loader2, CheckCircle, XCircle } from "lucide-react"

interface Template {
  TEMPLATE_ID: string
  NAME: string
  DISPLAY_NAME: string
  DESCRIPTION: string
  PERSONA: string
  STEPS: string
  VERSION: string
  STATUS: string
}

interface PipelineTool {
  TOOL_ID: string
  NAME: string
  TYPE: string
  DOMAIN: string
  COMPUTE_TYPE: string
  ESTIMATED_RUNTIME: string
  DESCRIPTION: string
}

interface ParamField {
  key: string
  defaultValue?: string
  required: boolean
  label: string
  placeholder?: string
}

const TEMPLATE_PARAMS: Record<string, ParamField[]> = {
  WF001: [
    { key: "seed_smiles", label: "Seed SMILES", required: true, placeholder: "e.g. CC(C)Cc1ccc(cc1)C(C)C(=O)O" },
    { key: "n_molecules", label: "Number of Molecules", required: false, defaultValue: "50" },
    { key: "target_sequence", label: "Target Protein Sequence", required: false, defaultValue: "MTEYKLVVVGAGGVGKSALTIQLIQNHFVDEYDPTIEDSY", placeholder: "Amino acid sequence (default: KRAS)" },
    { key: "target_pdb", label: "Target PDB ID", required: false, placeholder: "e.g. 6OIM (optional)" },
  ],
  WF002: [
    { key: "target_sequence", label: "Target Protein Sequence", required: true, placeholder: "Amino acid sequence" },
    { key: "seed_smiles", label: "Ligand SMILES (optional)", required: false, placeholder: "e.g. CC(=O)Oc1ccccc1C(=O)O" },
  ],
  WF003: [
    { key: "seed_smiles", label: "Seed SMILES", required: true, placeholder: "e.g. CC(C)Cc1ccc(cc1)C(C)C(=O)O" },
    { key: "n_molecules", label: "Number of Molecules", required: false, defaultValue: "10" },
    { key: "sequence", label: "Target Protein Sequence", required: false, defaultValue: "MTEYKLVVVGAGGVGKSALTIQLIQNHFVDEYDPTIEDSY", placeholder: "Amino acid sequence (default: KRAS)" },
    { key: "target_pdb", label: "Target PDB ID", required: false, placeholder: "e.g. 6OIM (optional)" },
  ],
  WF004: [
    { key: "expression_table", label: "Expression Table", required: true, placeholder: "e.g. WORKBENCH_PROJECTS.DEMO_NSCLC.GENE_EXPRESSION" },
    { key: "patients_table", label: "Patients Table", required: true, placeholder: "e.g. WORKBENCH_PROJECTS.DEMO_NSCLC.PATIENTS" },
    { key: "target_sequence", label: "Target Protein Sequence", required: false, placeholder: "Amino acid sequence (optional)" },
    { key: "gene_symbol", label: "Gene Symbol", required: false, placeholder: "e.g. KRAS (optional)" },
    { key: "query", label: "Literature Search Query", required: false, placeholder: "e.g. KRAS G12C resistance NSCLC" },
  ],
}

function getParamsForTemplate(templateId: string): ParamField[] {
  const defined = TEMPLATE_PARAMS[templateId] ?? []
  return [
    ...defined,
    { key: "output_table", label: "Output Table", required: true, defaultValue: "" },
  ]
}

function RunWorkflowDialog({ template, onClose }: { template: Template; onClose: () => void }) {
  const router = useRouter()
  const params = getParamsForTemplate(template.TEMPLATE_ID)
  const ts = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 15)
  const defaultOutput = `SCIENTIFIC_WORKBENCH.RESULTS.WF_${template.TEMPLATE_ID}_${ts}`

  const [values, setValues] = useState<Record<string, string>>(() => {
    const init: Record<string, string> = {}
    for (const p of params) {
      init[p.key] = p.key === "output_table" ? defaultOutput : (p.defaultValue ?? "")
    }
    return init
  })
  const [status, setStatus] = useState<"form" | "running" | "success" | "error">("form")
  const [error, setError] = useState("")
  const [summary, setSummary] = useState("")

  const allFilled = params.filter((p) => p.required).every((p) => values[p.key]?.trim())

  const handleRun = useCallback(async () => {
    setStatus("running")
    setError("")
    try {
      const res = await fetch("/api/workflows/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ template_name: template.NAME, params: values }),
      })
      const data = await res.json()
      if (!res.ok || data.error) {
        setError(data.error || `Request failed (${res.status})`)
        setStatus("error")
        return
      }
      const result = Array.isArray(data) ? data[0] : data
      setSummary(result?.AGENT_SUMMARY || result?.agent_summary || "Workflow completed.")
      setStatus("success")
    } catch (e) {
      setError(e instanceof Error ? e.message : "Unknown error")
      setStatus("error")
    }
  }, [template.NAME, values])

  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 100, display: "flex", alignItems: "center", justifyContent: "center" }}>
      <div onClick={status === "running" ? undefined : onClose} style={{ position: "absolute", inset: 0, background: "rgba(0,0,0,0.5)" }} />
      <div style={{ position: "relative", width: 480, maxHeight: "80vh", background: "var(--sf-card-bg)", borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", boxShadow: "var(--elevation-floating)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
        {/* Header */}
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "14px 20px", borderBottom: "1px solid var(--sf-border)", background: "var(--sf-dark)" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <Play size={14} style={{ color: "var(--sf-blue)" }} />
            <span style={{ fontSize: 14, fontWeight: 600, color: "var(--sf-text)" }}>Run: {template.DISPLAY_NAME}</span>
          </div>
          {status !== "running" && (
            <button onClick={onClose} style={{ background: "transparent", border: "none", color: "var(--sf-text-muted)", cursor: "pointer", padding: 2, display: "flex" }}>
              <X size={16} />
            </button>
          )}
        </div>

        {/* Body */}
        <div style={{ flex: 1, overflowY: "auto", padding: 20 }}>
          {status === "form" && (
            <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
              {params.map((p) => (
                <div key={p.key}>
                  <label style={{ display: "block", fontSize: 12, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4 }}>
                    {p.label} {p.required && <span style={{ color: "var(--role-critical)" }}>*</span>}
                  </label>
                  <input
                    value={values[p.key] || ""}
                    onChange={(e) => setValues((v) => ({ ...v, [p.key]: e.target.value }))}
                    placeholder={p.placeholder || p.defaultValue || `Enter ${p.label.toLowerCase()}`}
                    style={{ width: "100%", padding: "8px 10px", borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)", color: "var(--sf-text)", fontSize: 13, fontFamily: p.key.includes("table") || p.key.includes("smiles") || p.key.includes("sequence") ? "var(--font-fira-mono)" : "inherit" }}
                  />
                </div>
              ))}
            </div>
          )}

          {status === "running" && (
            <div style={{ textAlign: "center", padding: "32px 0" }}>
              <Loader2 size={32} style={{ margin: "0 auto 12px", color: "var(--sf-blue)", animation: "spin 1s linear infinite" }} />
              <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)", marginBottom: 4 }}>Running workflow...</div>
              <div style={{ fontSize: 12, color: "var(--sf-text-muted)" }}>This may take 30 seconds to several minutes depending on the workflow.</div>
              <style>{"@keyframes spin { to { transform: rotate(360deg) } }"}</style>
            </div>
          )}

          {status === "success" && (
            <div style={{ textAlign: "center", padding: "24px 0" }}>
              <CheckCircle size={32} style={{ margin: "0 auto 12px", color: "var(--role-success)" }} />
              <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)", marginBottom: 8 }}>Workflow completed</div>
              <div style={{ fontSize: 12, color: "var(--sf-text-muted)", marginBottom: 16 }}>{summary}</div>
              <button
                onClick={() => router.push(`/explore?table=${values.output_table}`)}
                style={{ padding: "8px 16px", borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-blue)", background: "var(--sf-blue)", color: "#fff", fontSize: 13, fontWeight: 500, cursor: "pointer" }}
              >
                View Results
              </button>
            </div>
          )}

          {status === "error" && (
            <div style={{ textAlign: "center", padding: "24px 0" }}>
              <XCircle size={32} style={{ margin: "0 auto 12px", color: "var(--role-critical)" }} />
              <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)", marginBottom: 8 }}>Workflow failed</div>
              <div style={{ fontSize: 12, color: "var(--role-critical)", marginBottom: 16, maxHeight: 100, overflowY: "auto" }}>{error}</div>
              <button
                onClick={() => setStatus("form")}
                style={{ padding: "6px 14px", borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)", color: "var(--sf-text)", fontSize: 12, cursor: "pointer" }}
              >
                Try again
              </button>
            </div>
          )}
        </div>

        {/* Footer */}
        {status === "form" && (
          <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, padding: "12px 20px", borderTop: "1px solid var(--sf-border)", background: "var(--sf-dark)" }}>
            <button onClick={onClose} style={{ padding: "6px 14px", borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)", color: "var(--sf-text)", fontSize: 12, cursor: "pointer" }}>
              Cancel
            </button>
            <button
              onClick={handleRun}
              disabled={!allFilled}
              style={{ padding: "6px 14px", borderRadius: "var(--radius-sm)", border: "none", background: allFilled ? "var(--sf-blue)" : "var(--sf-surface-2)", color: allFilled ? "#fff" : "var(--sf-text-muted)", fontSize: 12, fontWeight: 500, cursor: allFilled ? "pointer" : "not-allowed", display: "flex", alignItems: "center", gap: 4 }}
            >
              <Play size={12} /> Run Workflow
            </button>
          </div>
        )}
      </div>
    </div>
  )
}

function TemplateDetailPanel({ template }: { template: Template }) {
  let steps: { tool_name: string; description?: string }[] = []
  try { steps = JSON.parse(template.STEPS || "[]") } catch { /* empty */ }

  return (
    <div className="space-y-4">
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Workflow</div>
        <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)" }}>{template.DISPLAY_NAME || template.NAME}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Description</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)", lineHeight: 1.5 }}>{template.DESCRIPTION}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Personas</div>
        <div style={{ display: "flex", gap: 4, flexWrap: "wrap" }}>
          {String(template.PERSONA || "").split(",").filter(Boolean).map((p) => (
            <span key={p.trim()} style={{ fontSize: 11, padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "var(--role-info-bg)", color: "var(--sf-blue)" }}>{p.trim()}</span>
          ))}
        </div>
      </div>
      {steps.length > 0 && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 8, textTransform: "uppercase" }}>Steps ({steps.length})</div>
          <div className="space-y-2">
            {steps.map((step, i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 8 }}>
                <div style={{ width: 22, height: 22, borderRadius: "var(--radius-pill)", background: "var(--sf-surface-2)", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", flexShrink: 0 }}>
                  {i + 1}
                </div>
                <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{step.tool_name || (step as unknown as { name?: string }).name || `Step ${i + 1}`}</div>
                {i < steps.length - 1 && <ArrowRight size={12} style={{ color: "var(--sf-text-muted)", flexShrink: 0, marginLeft: "auto" }} />}
              </div>
            ))}
          </div>
        </div>
      )}
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Version</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>v{template.VERSION}</div>
      </div>
    </div>
  )
}

function PipelineDetailPanel({ tool }: { tool: PipelineTool }) {
  return (
    <div className="space-y-4">
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Pipeline</div>
        <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)" }}>{tool.NAME}</div>
      </div>
      <div style={{ display: "flex", gap: 6 }}>
        <span style={{ fontSize: 11, padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "var(--sf-surface-2)", color: "var(--sf-text-muted)" }}>{tool.DOMAIN}</span>
        {tool.COMPUTE_TYPE === "GPU" && (
          <span style={{ fontSize: 11, padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "#f0e6ff", color: "#7c3aed", display: "inline-flex", alignItems: "center", gap: 3 }}>
            <Zap size={10} /> GPU
          </span>
        )}
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Description</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)", lineHeight: 1.5 }}>{tool.DESCRIPTION}</div>
      </div>
      {tool.ESTIMATED_RUNTIME && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Estimated Runtime</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{tool.ESTIMATED_RUNTIME}</div>
        </div>
      )}
    </div>
  )
}

export function WorkflowsClient({ templates, pipelineTools }: { templates: Template[]; pipelineTools: PipelineTool[] }) {
  const { setDetail } = useDetailPanel()
  const [runningTemplate, setRunningTemplate] = useState<Template | null>(null)

  useEffect(() => {
    setDetail("Workflow Details", <DetailPanelEmpty icon={<GitBranch size={32} />} message="Select a workflow template or pipeline to view its steps and details." />)
  }, [setDetail])

  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)" }}>Workflows</h1>
        <span style={{ fontSize: 13, color: "var(--sf-text-muted)" }}>{templates.length + pipelineTools.length} available</span>
      </div>

      {/* Workflow Templates */}
      {templates.length > 0 && (
        <div style={{ marginBottom: 28 }}>
          <h2 style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text-muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 12 }}>
            Workflow Templates ({templates.length})
          </h2>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(320px, 1fr))", gap: 12 }}>
            {templates.map((t) => {
              let steps: unknown[] = []
              try { steps = JSON.parse(t.STEPS || "[]") } catch { /* empty */ }
              return (
                <div
                  key={t.TEMPLATE_ID}
                  onClick={() => setDetail("Workflow Details", <TemplateDetailPanel template={t} />)}
                  style={{
                    padding: 20, borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)",
                    background: "var(--sf-card-bg)", cursor: "pointer", transition: "box-shadow 0.12s, border-color 0.12s",
                    display: "flex", flexDirection: "column", gap: 12,
                  }}
                  onMouseEnter={(e) => { e.currentTarget.style.borderColor = "var(--sf-blue)"; e.currentTarget.style.boxShadow = "var(--elevation-raised)" }}
                  onMouseLeave={(e) => { e.currentTarget.style.borderColor = "var(--sf-border)"; e.currentTarget.style.boxShadow = "none" }}
                >
                  <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                    <div style={{ width: 36, height: 36, borderRadius: "var(--radius-sm)", background: "var(--role-info-bg)", color: "var(--sf-blue)", display: "flex", alignItems: "center", justifyContent: "center" }}>
                      <GitBranch size={18} />
                    </div>
                    <div>
                      <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)" }}>{t.DISPLAY_NAME || t.NAME}</div>
                      <div style={{ fontSize: 11, color: "var(--sf-text-muted)" }}>{steps.length} steps · v{t.VERSION}</div>
                    </div>
                  </div>
                  <p style={{ fontSize: 12, color: "var(--sf-text-muted)", lineHeight: 1.5, margin: 0, display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden" }}>
                    {t.DESCRIPTION}
                  </p>
                  <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                    <div style={{ display: "flex", gap: 4, flexWrap: "wrap" }}>
                      {String(t.PERSONA || "").split(",").filter(Boolean).slice(0, 2).map((p) => (
                        <span key={p.trim()} style={{ fontSize: 10, padding: "2px 6px", borderRadius: "var(--radius-xs)", background: "var(--sf-surface-2)", color: "var(--sf-text-muted)" }}>{p.trim()}</span>
                      ))}
                    </div>
                    <button
                      onClick={(e) => { e.stopPropagation(); setRunningTemplate(t) }}
                      style={{
                        display: "flex", alignItems: "center", gap: 4, padding: "4px 12px", borderRadius: "var(--radius-sm)",
                        border: "1px solid var(--sf-blue)", background: "var(--sf-card-bg)", fontSize: 12, fontWeight: 500,
                        color: "var(--sf-blue)", cursor: "pointer",
                      }}
                    >
                      <Play size={12} /> Run
                    </button>
                  </div>
                </div>
              )
            })}
          </div>
        </div>
      )}

      {/* Pipeline Tools */}
      {pipelineTools.length > 0 && (
        <div style={{ marginBottom: 28 }}>
          <h2 style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text-muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 12 }}>
            Multi-NIM Pipelines ({pipelineTools.length})
          </h2>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: 12 }}>
            {pipelineTools.map((tool) => (
              <div
                key={tool.TOOL_ID}
                onClick={() => setDetail("Workflow Details", <PipelineDetailPanel tool={tool} />)}
                style={{
                  padding: 16, borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)",
                  background: "var(--sf-card-bg)", cursor: "pointer", transition: "box-shadow 0.12s, border-color 0.12s",
                  display: "flex", flexDirection: "column", gap: 10,
                }}
                onMouseEnter={(e) => { e.currentTarget.style.borderColor = "var(--sf-blue)"; e.currentTarget.style.boxShadow = "var(--elevation-raised)" }}
                onMouseLeave={(e) => { e.currentTarget.style.borderColor = "var(--sf-border)"; e.currentTarget.style.boxShadow = "none" }}
              >
                <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                  <div style={{ width: 36, height: 36, borderRadius: "var(--radius-sm)", background: "#f0e6ff", color: "#7c3aed", display: "flex", alignItems: "center", justifyContent: "center" }}>
                    <GitBranch size={18} />
                  </div>
                  <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)" }}>{tool.NAME}</div>
                  {tool.COMPUTE_TYPE === "GPU" && (
                    <span style={{ fontSize: 10, fontWeight: 600, padding: "2px 6px", borderRadius: "var(--radius-xs)", background: "#f0e6ff", color: "#7c3aed", marginLeft: "auto" }}>GPU</span>
                  )}
                </div>
                <p style={{ fontSize: 12, color: "var(--sf-text-muted)", lineHeight: 1.5, margin: 0, display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden" }}>
                  {tool.DESCRIPTION}
                </p>
              </div>
            ))}
          </div>
        </div>
      )}

      {templates.length === 0 && pipelineTools.length === 0 && (
        <div style={{ padding: 60, textAlign: "center", color: "var(--sf-text-muted)" }}>
          <GitBranch size={48} style={{ margin: "0 auto 12px", opacity: 0.3 }} />
          <p style={{ fontSize: 14 }}>No workflow templates available.</p>
        </div>
      )}

      {runningTemplate && (
        <RunWorkflowDialog template={runningTemplate} onClose={() => setRunningTemplate(null)} />
      )}
    </div>
  )
}
