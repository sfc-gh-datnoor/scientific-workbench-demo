"use client"

import { useState, useEffect, useCallback } from "react"
import { useDetailPanel } from "@/components/detail-panel-context"
import { DetailPanelEmpty } from "@/components/detail-panel-empty"
import { Search, Package, Table2, Columns3, Eye } from "lucide-react"
import { toRows, queryError } from "@/lib/query-rows"

interface Asset {
  ASSET_ID?: string
  ASSET_NAME: string
  ASSET_TYPE: string
  DESCRIPTION: string
  PROGRAM?: string
  OWNER?: string
  SCHEMA_NAME?: string
  ROW_COUNT?: number
  QUALITY_STATUS?: string
  CREATED_AT?: string
}

interface ColumnInfo {
  COLUMN_NAME: string
  DATA_TYPE: string
  IS_NULLABLE: string
  CHARACTER_MAXIMUM_LENGTH: number | null
}

const PREVIEWABLE_TYPES = new Set(["dataset", "view", "table"])

function AssetMetadataSection({ asset }: { asset: Asset }) {
  return (
    <div className="space-y-3">
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Name</div>
        <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)" }}>{asset.ASSET_NAME}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Type</div>
        <span style={{ fontSize: 12, padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "var(--role-info-bg)", color: "var(--sf-blue)" }}>{asset.ASSET_TYPE}</span>
      </div>
      {asset.DESCRIPTION && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Description</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)", lineHeight: 1.5 }}>{asset.DESCRIPTION}</div>
        </div>
      )}
      {asset.SCHEMA_NAME && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Location</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)", fontFamily: "var(--font-fira-mono)" }}>{asset.SCHEMA_NAME}.{asset.ASSET_NAME}</div>
        </div>
      )}
      {asset.PROGRAM && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Program</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{asset.PROGRAM}</div>
        </div>
      )}
      {asset.OWNER && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Owner</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{asset.OWNER}</div>
        </div>
      )}
      {(asset.ROW_COUNT != null && asset.ROW_COUNT > 0) && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Rows</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{asset.ROW_COUNT.toLocaleString()}</div>
        </div>
      )}
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Created</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{asset.CREATED_AT ? new Date(asset.CREATED_AT).toLocaleDateString() : "-"}</div>
      </div>
    </div>
  )
}

function AssetDetailPanel({ asset }: { asset: Asset }) {
  const [tab, setTab] = useState<"info" | "schema" | "preview">("info")
  const [columns, setColumns] = useState<ColumnInfo[]>([])
  const [previewRows, setPreviewRows] = useState<Record<string, unknown>[]>([])
  const [loadingSchema, setLoadingSchema] = useState(false)
  const [loadingPreview, setLoadingPreview] = useState(false)
  const [schemaError, setSchemaError] = useState<string | null>(null)
  const [previewError, setPreviewError] = useState<string | null>(null)

  const isPreviewable = PREVIEWABLE_TYPES.has(asset.ASSET_TYPE?.toLowerCase())

  const loadSchema = useCallback(async () => {
    if (!asset.SCHEMA_NAME || columns.length > 0) return
    setLoadingSchema(true)
    setSchemaError(null)
    try {
      const res = await fetch("/api/query", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: "asset_column_info", params: { schema_name: asset.SCHEMA_NAME, asset_name: asset.ASSET_NAME } }),
      })
      const data = await res.json()
      const qErr = queryError(data)
      if (qErr) { setSchemaError(qErr); return }
      setColumns(toRows<ColumnInfo>(data))
    } catch (e) {
      setSchemaError(e instanceof Error ? e.message : "Failed to load schema")
    } finally {
      setLoadingSchema(false)
    }
  }, [asset.SCHEMA_NAME, asset.ASSET_NAME, columns.length])

  const loadPreview = useCallback(async () => {
    if (!asset.SCHEMA_NAME || previewRows.length > 0) return
    setLoadingPreview(true)
    setPreviewError(null)
    try {
      const res = await fetch("/api/query", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: "asset_preview", params: { schema_name: asset.SCHEMA_NAME, asset_name: asset.ASSET_NAME, limit: 20 } }),
      })
      const data = await res.json()
      const qErr = queryError(data)
      if (qErr) { setPreviewError(qErr); return }
      setPreviewRows(toRows<Record<string, unknown>>(data))
    } catch (e) {
      setPreviewError(e instanceof Error ? e.message : "Failed to load preview")
    } finally {
      setLoadingPreview(false)
    }
  }, [asset.SCHEMA_NAME, asset.ASSET_NAME, previewRows.length])

  useEffect(() => {
    if (tab === "schema" && isPreviewable) loadSchema()
    if (tab === "preview" && isPreviewable) loadPreview()
  }, [tab, isPreviewable, loadSchema, loadPreview])

  const tabStyle = (active: boolean) => ({
    padding: "6px 12px",
    fontSize: 12,
    fontWeight: active ? 600 : 400,
    color: active ? "var(--sf-blue)" : "var(--sf-text-muted)",
    borderBottom: active ? "2px solid var(--sf-blue)" : "2px solid transparent",
    background: "none",
    border: "none",
    borderBottomStyle: "solid" as const,
    borderBottomWidth: 2,
    borderBottomColor: active ? "var(--sf-blue)" : "transparent",
    cursor: "pointer",
    display: "flex",
    alignItems: "center",
    gap: 4,
  })

  return (
    <div>
      {isPreviewable && asset.SCHEMA_NAME && (
        <div style={{ display: "flex", gap: 0, borderBottom: "1px solid var(--sf-border)", marginBottom: 12 }}>
          <button onClick={() => setTab("info")} style={tabStyle(tab === "info")}><Package size={12} /> Info</button>
          <button onClick={() => setTab("schema")} style={tabStyle(tab === "schema")}><Columns3 size={12} /> Schema</button>
          <button onClick={() => setTab("preview")} style={tabStyle(tab === "preview")}><Eye size={12} /> Preview</button>
        </div>
      )}

      {tab === "info" && <AssetMetadataSection asset={asset} />}

      {tab === "schema" && (
        <div>
          {loadingSchema && <div style={{ padding: 20, textAlign: "center", color: "var(--sf-text-muted)", fontSize: 13 }}>Loading schema...</div>}
          {schemaError && <div style={{ padding: 10, fontSize: 12, color: "var(--role-critical, #ef4444)" }}>{schemaError}</div>}
          {!loadingSchema && !schemaError && columns.length === 0 && <div style={{ padding: 20, textAlign: "center", color: "var(--sf-text-muted)", fontSize: 13 }}>No columns found</div>}
          {columns.length > 0 && (
            <div className="space-y-2">
              <div style={{ fontSize: 12, color: "var(--sf-text-muted)", marginBottom: 8 }}>{columns.length} columns</div>
              {columns.map((col) => (
                <div key={col.COLUMN_NAME} style={{ padding: "6px 8px", borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)" }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                    <span style={{ fontSize: 12, fontWeight: 500, color: "var(--sf-text)", fontFamily: "var(--font-fira-mono)" }}>{col.COLUMN_NAME}</span>
                    <span style={{ fontSize: 11, padding: "1px 6px", borderRadius: "var(--radius-xs)", background: "var(--role-info-bg)", color: "var(--sf-blue)" }}>{col.DATA_TYPE}</span>
                  </div>
                  <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 2 }}>
                    {col.IS_NULLABLE === "YES" ? "Nullable" : "Required"}
                    {col.CHARACTER_MAXIMUM_LENGTH ? ` · Max: ${col.CHARACTER_MAXIMUM_LENGTH}` : ""}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {tab === "preview" && (
        <div>
          {loadingPreview && <div style={{ padding: 20, textAlign: "center", color: "var(--sf-text-muted)", fontSize: 13 }}>Loading preview...</div>}
          {previewError && <div style={{ padding: 10, fontSize: 12, color: "var(--role-critical, #ef4444)" }}>{previewError}</div>}
          {!loadingPreview && !previewError && previewRows.length === 0 && <div style={{ padding: 20, textAlign: "center", color: "var(--sf-text-muted)", fontSize: 13 }}>No data</div>}
          {previewRows.length > 0 && (
            <div style={{ overflow: "auto", maxHeight: "calc(100vh - 200px)" }}>
              <div style={{ fontSize: 12, color: "var(--sf-text-muted)", marginBottom: 8 }}>Showing {previewRows.length} rows</div>
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 11, fontFamily: "var(--font-fira-mono)" }}>
                <thead>
                  <tr style={{ background: "var(--sf-dark)" }}>
                    {Object.keys(previewRows[0]).map((key) => (
                      <th key={key} style={{ padding: "4px 8px", textAlign: "left", fontWeight: 600, fontSize: 10, color: "var(--sf-text-muted)", borderBottom: "1px solid var(--sf-border)", whiteSpace: "nowrap" }}>{key}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {previewRows.map((row, i) => (
                    <tr key={i} style={{ borderBottom: "1px solid var(--sf-border)" }}>
                      {Object.values(row).map((val, j) => (
                        <td key={j} style={{ padding: "4px 8px", color: "var(--sf-text)", maxWidth: 200, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                          {val == null ? <span style={{ color: "var(--sf-text-muted)", fontStyle: "italic" }}>null</span> : String(val)}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

export default function CatalogPage() {
  const [assets, setAssets] = useState<Asset[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [searchQuery, setSearchQuery] = useState("")
  const [typeFilter, setTypeFilter] = useState<string>("all")
  const { setDetail } = useDetailPanel()

  useEffect(() => {
    setDetail("Asset Details", <DetailPanelEmpty icon={<Package size={32} />} message="Select an asset from the table to view details, schema, and data preview." />)
  }, [setDetail])

  useEffect(() => {
    async function load() {
      try {
        const res = await fetch("/api/query", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: "assets_list" }),
        })
        const data = await res.json()
        const rows = toRows<Asset>(data)
        const qErr = queryError(data)
        if (qErr) setError(qErr)
        setAssets(rows)
      } catch (e) {
        setError(e instanceof Error ? e.message : "Failed to load assets")
        setAssets([])
      }
      setLoading(false)
    }
    load()
  }, [])

  const types = Array.from(new Set(assets.map((a) => a.ASSET_TYPE).filter(Boolean)))
  const filtered = assets.filter((a) => {
    if (typeFilter !== "all" && a.ASSET_TYPE !== typeFilter) return false
    if (searchQuery) {
      const q = searchQuery.toLowerCase()
      const inName = (a.ASSET_NAME || "").toLowerCase().includes(q)
      const inDesc = (a.DESCRIPTION || "").toLowerCase().includes(q)
      const inProg = (a.PROGRAM || "").toLowerCase().includes(q)
      if (!inName && !inDesc && !inProg) return false
    }
    return true
  })

  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)" }}>Asset Catalog</h1>
        <span style={{ fontSize: 13, color: "var(--sf-text-muted)" }}>{filtered.length} assets</span>
      </div>

      <div style={{ display: "flex", gap: 12, marginBottom: 16 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 6, padding: "6px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)", flex: 1 }}>
          <Search size={14} style={{ color: "var(--sf-text-muted)" }} />
          <input value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} placeholder="Search assets..." style={{ flex: 1, border: "none", outline: "none", background: "transparent", fontSize: 13, color: "var(--sf-text)" }} />
        </div>
        <select
          value={typeFilter} onChange={(e) => setTypeFilter(e.target.value)}
          style={{ padding: "6px 12px", borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)", fontSize: 13, color: "var(--sf-text)" }}
        >
          <option value="all">All types</option>
          {types.map((t) => <option key={t} value={t}>{t}</option>)}
        </select>
      </div>

      {error && (
        <div style={{ marginBottom: 16, padding: "10px 14px", borderRadius: "var(--radius-sm)", border: "1px solid var(--role-critical, #7f1d1d)", background: "var(--role-critical-bg, #2a1215)", fontSize: 13, color: "var(--sf-text)" }}>
          <strong style={{ fontWeight: 600 }}>Could not load assets.</strong>{" "}
          <span style={{ fontFamily: "var(--font-fira-mono)", fontSize: 12 }}>{error}</span>
        </div>
      )}

      {loading ? (
        <div style={{ padding: 40, textAlign: "center", color: "var(--sf-text-muted)" }}>Loading assets...</div>
      ) : (
        <div style={{ borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", overflow: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
            <thead>
              <tr style={{ background: "var(--sf-dark)" }}>
                <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Name</th>
                <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Type</th>
                <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Location</th>
                <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Owner</th>
                <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Status</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((a, i) => (
                <tr
                  key={a.ASSET_ID || i}
                  onClick={() => setDetail("Asset Details", <AssetDetailPanel asset={a} />)}
                  style={{ borderBottom: "1px solid var(--sf-border)", cursor: "pointer", transition: "background 0.1s" }}
                  onMouseEnter={(e) => (e.currentTarget.style.background = "var(--sf-surface-2)")}
                  onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
                >
                  <td style={{ padding: "8px 12px", color: "var(--sf-text)", fontWeight: 500 }}>{a.ASSET_NAME}</td>
                  <td style={{ padding: "8px 12px" }}>
                    <span style={{ fontSize: 12, padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "var(--sf-surface-2)", color: "var(--sf-text-muted)" }}>{a.ASSET_TYPE}</span>
                  </td>
                  <td style={{ padding: "8px 12px", color: "var(--sf-text-muted)", fontFamily: "var(--font-fira-mono)", fontSize: 12 }}>{a.SCHEMA_NAME || "-"}</td>
                  <td style={{ padding: "8px 12px", color: "var(--sf-text-muted)" }}>{a.OWNER || "-"}</td>
                  <td style={{ padding: "8px 12px", color: "var(--sf-text-muted)" }}>{a.QUALITY_STATUS || "-"}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {filtered.length === 0 && <div style={{ padding: 40, textAlign: "center", color: "var(--sf-text-muted)" }}>No assets found</div>}
        </div>
      )}
    </div>
  )
}
