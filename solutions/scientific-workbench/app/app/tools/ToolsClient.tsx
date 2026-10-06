"use client"

import { useState, useEffect } from "react"
import { useRouter } from "next/navigation"
import { useDetailPanel } from "@/components/detail-panel-context"
import { DetailPanelEmpty } from "@/components/detail-panel-empty"
import { Wrench, Play, Zap, Plus, Shield } from "lucide-react"

interface Tool {
  TOOL_ID: string
  NAME: string
  TYPE: string
  DOMAIN: string
  COMPUTE_TYPE: string
  ESTIMATED_RUNTIME: string
  DESCRIPTION: string
  INPUT_SCHEMA: string
  OUTPUT_SCHEMA: string
}

function ToolDetailPanel({ tool }: { tool: Tool }) {
  let inputSchema: { name: string; type: string; description?: string }[] = []
  try { inputSchema = JSON.parse(tool.INPUT_SCHEMA || "[]") } catch { /* empty */ }

  return (
    <div className="space-y-4">
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Tool</div>
        <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)" }}>{tool.NAME}</div>
      </div>
      <div style={{ display: "flex", gap: 6 }}>
        <span style={{ fontSize: 11, padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "var(--role-info-bg)", color: "var(--sf-blue)" }}>{tool.TYPE}</span>
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
      {Array.isArray(inputSchema) && inputSchema.length > 0 && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 8, textTransform: "uppercase" }}>Input Parameters</div>
          <div className="space-y-2">
            {inputSchema.map((p) => (
              <div key={p.name} style={{ padding: "6px 8px", borderRadius: "var(--radius-xs)", border: "1px solid var(--sf-border)" }}>
                <div style={{ display: "flex", justifyContent: "space-between" }}>
                  <span style={{ fontSize: 12, fontWeight: 500, fontFamily: "var(--font-fira-mono)", color: "var(--sf-text)" }}>{p.name}</span>
                  <span style={{ fontSize: 11, color: "var(--sf-text-muted)" }}>{p.type}</span>
                </div>
                {p.description && <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 2 }}>{p.description}</div>}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function getInitials(name: string) {
  return name.split(/[\s-]+/).map((w) => w[0]).join("").toUpperCase().slice(0, 2)
}

const AVATAR_COLORS = [
  { bg: "#e3efff", fg: "#2365d1" }, { bg: "#e7f4ec", fg: "#1f8b4c" },
  { bg: "#fbeae7", fg: "#c5331f" }, { bg: "#fbf1da", fg: "#9a6700" },
  { bg: "#f0e6ff", fg: "#7c3aed" }, { bg: "#e0f7fa", fg: "#0097a7" },
]

export function ToolsClient({ tools }: { tools: Tool[] }) {
  const { setDetail } = useDetailPanel()
  const router = useRouter()

  useEffect(() => {
    setDetail("Tool Details", <DetailPanelEmpty icon={<Wrench size={32} />} message="Select a tool to view its parameters and details." />)
  }, [setDetail])

  const grouped = new Map<string, Tool[]>()
  for (const t of tools) {
    const key = t.TYPE
    if (!grouped.has(key)) grouped.set(key, [])
    grouped.get(key)!.push(t)
  }

  const TYPE_LABELS: Record<string, string> = {
    nim: "NVIDIA NIM Microservices",
    "open-model": "Open Model Tools",
    native: "Snowflake Native Tools",
    container: "Container Services",
    library: "Library Functions",
  }

  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)" }}>Tools</h1>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <span style={{ fontSize: 13, color: "var(--sf-text-muted)" }}>{tools.length} tools</span>
          <button onClick={() => router.push("/tools/submissions")}
            style={{ padding: "6px 12px", fontSize: 12, fontWeight: 500, borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", background: "var(--sf-surface-1)", color: "var(--sf-text-muted)", cursor: "pointer", display: "inline-flex", alignItems: "center", gap: 4 }}>
            <Shield size={12} /> Review Queue
          </button>
          <button onClick={() => router.push("/tools/onboard")}
            style={{ padding: "6px 12px", fontSize: 12, fontWeight: 500, borderRadius: "var(--radius-sm)", border: "none", background: "var(--sf-blue)", color: "#fff", cursor: "pointer", display: "inline-flex", alignItems: "center", gap: 4 }}>
            <Plus size={12} /> Add Custom Tool
          </button>
        </div>
      </div>
      {tools.length === 0 ? (
        <div style={{ padding: 60, textAlign: "center", color: "var(--sf-text-muted)" }}>
          <Wrench size={48} style={{ margin: "0 auto 12px", opacity: 0.3 }} />
          <p style={{ fontSize: 14 }}>No tools registered yet.</p>
        </div>
      ) : (
        Array.from(grouped).map(([type, typeTools]) => (
          <div key={type} style={{ marginBottom: 28 }}>
            <h2 style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text-muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 12 }}>
              {TYPE_LABELS[type] || type} ({typeTools.length})
            </h2>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(280px, 1fr))", gap: 12 }}>
              {typeTools.map((tool, idx) => {
                const color = AVATAR_COLORS[idx % AVATAR_COLORS.length]
                return (
                  <div
                    key={tool.TOOL_ID}
                    onClick={() => setDetail("Tool Details", <ToolDetailPanel tool={tool} />)}
                    style={{
                      padding: 16, borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)",
                      background: "var(--sf-card-bg)", cursor: "pointer", transition: "box-shadow 0.12s, border-color 0.12s",
                      display: "flex", flexDirection: "column", gap: 10,
                    }}
                    onMouseEnter={(e) => { e.currentTarget.style.borderColor = "var(--sf-blue)"; e.currentTarget.style.boxShadow = "var(--elevation-raised)" }}
                    onMouseLeave={(e) => { e.currentTarget.style.borderColor = "var(--sf-border)"; e.currentTarget.style.boxShadow = "none" }}
                  >
                    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                      <div style={{ width: 36, height: 36, borderRadius: "var(--radius-sm)", background: color.bg, color: color.fg, display: "flex", alignItems: "center", justifyContent: "center", fontSize: 13, fontWeight: 600, flexShrink: 0 }}>
                        {getInitials(tool.NAME)}
                      </div>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)" }}>{tool.NAME}</div>
                      </div>
                      {tool.COMPUTE_TYPE === "GPU" && (
                        <span style={{ fontSize: 10, fontWeight: 600, padding: "2px 6px", borderRadius: "var(--radius-xs)", background: "#f0e6ff", color: "#7c3aed", display: "flex", alignItems: "center", gap: 3 }}>
                          <Zap size={10} /> GPU
                        </span>
                      )}
                    </div>
                    <p style={{ fontSize: 12, color: "var(--sf-text-muted)", lineHeight: 1.5, margin: 0, flex: 1, display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden" }}>
                      {tool.DESCRIPTION}
                    </p>
                    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                      <span style={{ fontSize: 11, color: "var(--sf-text-muted)" }}>{tool.DOMAIN}</span>
                      {tool.ESTIMATED_RUNTIME && <span style={{ fontSize: 11, color: "var(--sf-text-muted)" }}>{tool.ESTIMATED_RUNTIME}</span>}
                    </div>
                  </div>
                )
              })}
            </div>
          </div>
        ))
      )}
    </div>
  )
}
