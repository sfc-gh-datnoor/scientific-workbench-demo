"use client"

import { useCallback, useEffect, useState } from "react"
import { useDetailPanel } from "@/components/detail-panel-context"
import { DetailPanelEmpty } from "@/components/detail-panel-empty"
import { BookOpen, ExternalLink, Loader2 } from "lucide-react"

interface NotebookEntry {
  name: string
  filename: string
  size: number
  last_modified: string
  workspace: string
}

const ICON_MAP: Record<string, string> = {
  DRUG_DISCOVERY: "\u{1F48A}",
  PROTEIN: "\u{1F9EC}",
  GENE_EXPRESSION: "\u{1F52C}",
  SINGLE_CELL: "\u{1F535}",
  MOLECULAR: "\u{2697}\u{FE0F}",
  CLINICAL: "\u{1F4CA}",
}

function notebookIcon(name: string): string {
  const upper = name.toUpperCase()
  for (const [key, icon] of Object.entries(ICON_MAP)) {
    if (upper.includes(key)) return icon
  }
  return "\u{1F4D3}"
}

function formatName(name: string): string {
  return name
    .split("_")
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join(" ")
}

function getWorkspaceUrl(workspace: string): string | null {
  if (typeof window === "undefined") return null
  const host = window.location.hostname
  const appPart = host.split(".")[0]
  const match = appPart.match(/[a-z\d]+-(.+)/)
  const orgAccount = match ? match[1] : appPart
  return `https://app.snowflake.com/${orgAccount}/projects/workspaces`
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function NotebookDetailPanel({ nb }: { nb: NotebookEntry }) {
  return (
    <div className="space-y-4">
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Notebook</div>
        <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)" }}>{formatName(nb.name)}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Workspace</div>
        <div style={{ fontSize: 12, fontFamily: "var(--font-fira-mono)", color: "var(--sf-text-muted)" }}>{nb.workspace}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>File</div>
        <div style={{ fontSize: 12, fontFamily: "var(--font-fira-mono)", color: "var(--sf-text-muted)" }}>{nb.filename}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Size</div>
        <div style={{ fontSize: 12, color: "var(--sf-text-muted)" }}>{formatSize(nb.size)}</div>
      </div>
      {nb.last_modified && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Last Modified</div>
          <div style={{ fontSize: 12, color: "var(--sf-text-muted)" }}>{new Date(nb.last_modified).toLocaleString()}</div>
        </div>
      )}
    </div>
  )
}

export default function NotebooksPage() {
  const { setDetail } = useDetailPanel()
  const [notebooks, setNotebooks] = useState<NotebookEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const loadNotebooks = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch("/api/notebooks")
      const data = await res.json()
      if (data.error) setError(data.error as string)
      setNotebooks((data.notebooks ?? []) as NotebookEntry[])
    } catch {
      setError("Failed to load notebooks")
      setNotebooks([])
    }
    setLoading(false)
  }, [])

  useEffect(() => {
    setDetail("Notebook Details", <DetailPanelEmpty icon={<BookOpen size={32} />} message="Select a notebook to view its details." />)
    loadNotebooks()
  }, [setDetail, loadNotebooks])

  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)" }}>Notebooks</h1>
        <span style={{ fontSize: 13, color: "var(--sf-text-muted)" }}>
          {loading ? "Loading..." : `${notebooks.length} notebook${notebooks.length !== 1 ? "s" : ""}`}
        </span>
      </div>

      {loading && (
        <div style={{ padding: 40, textAlign: "center", color: "var(--sf-text-muted)" }}>
          <Loader2 size={24} className="animate-spin" style={{ margin: "0 auto 12px" }} />
          <div style={{ fontSize: 13 }}>Loading notebooks...</div>
        </div>
      )}

      {!loading && error && (
        <div style={{ padding: "12px 16px", borderRadius: "var(--radius-sm)", background: "#fbeae7", color: "#c5331f", fontSize: 13 }}>
          {error}
        </div>
      )}

      {!loading && !error && notebooks.length === 0 && (
        <div style={{ padding: 40, textAlign: "center", color: "var(--sf-text-muted)", fontSize: 13 }}>
          No notebooks found. Upload .ipynb files to the SCIENTIFIC_WORKBENCH_NOTEBOOKS workspace.
        </div>
      )}

      {!loading && notebooks.length > 0 && (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(300px, 1fr))", gap: 16 }}>
          {notebooks.map((nb) => {
            const url = getWorkspaceUrl(nb.workspace)
            return (
              <div
                key={nb.name}
                onClick={() => setDetail("Notebook Details", <NotebookDetailPanel nb={nb} />)}
                style={{
                  padding: 20, borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)",
                  background: "var(--sf-card-bg)", cursor: "pointer", transition: "box-shadow 0.12s, border-color 0.12s",
                  display: "flex", flexDirection: "column", gap: 12,
                }}
                onMouseEnter={(e) => { e.currentTarget.style.borderColor = "var(--sf-blue)"; e.currentTarget.style.boxShadow = "var(--elevation-raised)" }}
                onMouseLeave={(e) => { e.currentTarget.style.borderColor = "var(--sf-border)"; e.currentTarget.style.boxShadow = "none" }}
              >
                <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                  <span style={{ fontSize: 24 }}>{notebookIcon(nb.name)}</span>
                  <div>
                    <h3 style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)", margin: 0 }}>{formatName(nb.name)}</h3>
                    <div style={{ fontSize: 11, color: "var(--sf-text-muted)" }}>{formatSize(nb.size)}</div>
                  </div>
                </div>
                <div style={{ display: "flex", alignItems: "center", justifyContent: "flex-end" }}>
                  {url ? (
                    <a
                      href={url}
                      target="_blank"
                      rel="noopener noreferrer"
                      onClick={(e) => e.stopPropagation()}
                      style={{ display: "flex", alignItems: "center", gap: 4, fontSize: 12, color: "var(--sf-blue)", textDecoration: "none" }}
                    >
                      <ExternalLink size={12} /> Open in Workspaces
                    </a>
                  ) : (
                    <span style={{ fontSize: 11, color: "var(--sf-text-muted)", fontStyle: "italic" }}>No link available</span>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
