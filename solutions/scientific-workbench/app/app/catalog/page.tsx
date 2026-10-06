"use client"

import { useState, useEffect } from "react"
import { useDetailPanel } from "@/components/detail-panel-context"
import { DetailPanelEmpty } from "@/components/detail-panel-empty"
import { Search, Package } from "lucide-react"
import { toRows, queryError } from "@/lib/query-rows"

// Actual columns: ASSET_ID, NAME, TYPE, PROGRAM, OWNER, DESCRIPTION,
// CREATED_DATE, UPDATED_DATE, QUALITY_STATUS, TAGS, _LOADED_TIMESTAMP.
// The query aliases NAME→ASSET_NAME, TYPE→ASSET_TYPE, CREATED_DATE→CREATED_AT
// so the UI can use consistent field names.
interface Asset {
  ASSET_ID?: string
  ASSET_NAME: string
  ASSET_TYPE: string
  DESCRIPTION: string
  PROGRAM?: string
  OWNER?: string
  QUALITY_STATUS?: string
  CREATED_AT?: string
}

function RelatedAssetsPanel({ asset }: { asset: Asset }) {
  return (
    <div className="space-y-4">
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
      {asset.PROGRAM && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Program</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{asset.PROGRAM}</div>
        </div>
      )}
      {asset.QUALITY_STATUS && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Quality Status</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{asset.QUALITY_STATUS}</div>
        </div>
      )}
      {asset.OWNER && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Owner</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{asset.OWNER}</div>
        </div>
      )}

      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Created</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{asset.CREATED_AT ? new Date(asset.CREATED_AT).toLocaleDateString() : "-"}</div>
      </div>
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
    setDetail("Related Assets", <DetailPanelEmpty icon={<Package size={32} />} message="Select an asset from the table to view related metadata and details." />)
  }, [setDetail])

  useEffect(() => {
    async function load() {
      try {
        const res = await fetch("/api/query", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ sql: "SELECT ASSET_ID, NAME AS ASSET_NAME, TYPE AS ASSET_TYPE, PROGRAM, OWNER, DESCRIPTION, QUALITY_STATUS, CREATED_DATE AS CREATED_AT FROM SCIENTIFIC_WORKBENCH.CATALOG.ASSETS ORDER BY CREATED_DATE DESC NULLS LAST LIMIT 200" }),
        })
        const data = await res.json()
        // Only accept an array. /api/query answers a failed query with a JSON
        // error object and a non-2xx status, and res.json() resolves fine for it,
        // so `data.rows || data` used to assign that object straight into state.
        // The next assets.map() then threw and took the whole page down with
        // "This page couldn't load" instead of showing an empty table.
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
                <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Program</th>
                <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Owner</th>
                <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Status</th>
              </tr>
            </thead>
            <tbody>
              {filtered.map((a, i) => (
                <tr
                  key={a.ASSET_ID || i}
                  onClick={() => setDetail("Related Assets", <RelatedAssetsPanel asset={a} />)}
                  style={{ borderBottom: "1px solid var(--sf-border)", cursor: "pointer", transition: "background 0.1s" }}
                  onMouseEnter={(e) => (e.currentTarget.style.background = "var(--sf-surface-2)")}
                  onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
                >
                  <td style={{ padding: "8px 12px", color: "var(--sf-text)", fontWeight: 500 }}>{a.ASSET_NAME}</td>
                  <td style={{ padding: "8px 12px" }}>
                    <span style={{ fontSize: 12, padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "var(--sf-surface-2)", color: "var(--sf-text-muted)" }}>{a.ASSET_TYPE}</span>
                  </td>
                  <td style={{ padding: "8px 12px", color: "var(--sf-text-muted)" }}>{a.PROGRAM || "-"}</td>
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
