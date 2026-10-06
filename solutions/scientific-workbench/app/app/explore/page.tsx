"use client"

import { useState, useEffect, useCallback, Suspense } from "react"
import { useSearchParams } from "next/navigation"
import { useDetailPanel } from "@/components/detail-panel-context"
import { DetailPanelEmpty } from "@/components/detail-panel-empty"
import { ChevronRight, ChevronDown, Table2, Search } from "lucide-react"
import { toRows } from "@/lib/query-rows"

interface SchemaEntry {
  schema: string
  tables: string[]
}

interface ColumnInfo {
  COLUMN_NAME: string
  DATA_TYPE: string
  IS_NULLABLE: string
  CHARACTER_MAXIMUM_LENGTH: number | null
}

function DataProfilingPanel({ table, columns }: { table: string; columns: ColumnInfo[] }) {
  return (
    <div className="space-y-3">
      <div style={{ fontSize: 12, color: "var(--sf-text-muted)", marginBottom: 8 }}>
        {columns.length} columns in {table}
      </div>
      {columns.map((col) => (
        <div key={col.COLUMN_NAME} style={{ padding: "8px 10px", borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)" }}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 4 }}>
            <span style={{ fontSize: 13, fontWeight: 500, color: "var(--sf-text)", fontFamily: "var(--font-fira-mono)" }}>{col.COLUMN_NAME}</span>
            <span style={{ fontSize: 11, padding: "1px 6px", borderRadius: "var(--radius-xs)", background: "var(--role-info-bg)", color: "var(--sf-blue)" }}>{col.DATA_TYPE}</span>
          </div>
          <div style={{ fontSize: 11, color: "var(--sf-text-muted)" }}>
            {col.IS_NULLABLE === "YES" ? "Nullable" : "Required"}
            {col.CHARACTER_MAXIMUM_LENGTH ? ` · Max length: ${col.CHARACTER_MAXIMUM_LENGTH}` : ""}
          </div>
        </div>
      ))}
    </div>
  )
}

export default function ExplorePage() {
  return (
    <Suspense>
      <ExplorePageInner />
    </Suspense>
  )
}

function ExplorePageInner() {
  const [schemas, setSchemas] = useState<SchemaEntry[]>([])
  const [expandedSchema, setExpandedSchema] = useState<string | null>(null)
  const [selectedTable, setSelectedTable] = useState<string | null>(null)
  const [columns, setColumns] = useState<ColumnInfo[]>([])
  const [sampleData, setSampleData] = useState<Record<string, unknown>[]>([])
  const [loadingSchemas, setLoadingSchemas] = useState(true)
  const [loadingTable, setLoadingTable] = useState(false)
  const [searchFilter, setSearchFilter] = useState("")
  const { setDetail } = useDetailPanel()
  const searchParams = useSearchParams()
  const tableParam = searchParams.get("table")

  useEffect(() => {
    setDetail("Data Profiling", <DetailPanelEmpty icon={<Table2 size={32} />} message="Select a table from the schema browser to view column profiling details." />)
  }, [setDetail])

  useEffect(() => {
    async function loadSchemas() {
      try {
        const res = await fetch("/api/query", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: "schema_tables" }),
        })
        const data = await res.json()
        // Guard: a failed query returns a JSON error object, not an array.
        const rows = toRows<Record<string, unknown>>(data)
        const schemaMap = new Map<string, string[]>()
        for (const row of rows) {
          const s = (row as Record<string, string>).TABLE_SCHEMA
          const t = (row as Record<string, string>).TABLE_NAME
          if (!schemaMap.has(s)) schemaMap.set(s, [])
          schemaMap.get(s)!.push(t)
        }
        setSchemas(Array.from(schemaMap, ([schema, tables]) => ({ schema, tables })))
      } catch { setSchemas([]) }
      setLoadingSchemas(false)
    }
    loadSchemas()
  }, [])

  const selectTable = useCallback(async (schema: string, table: string) => {
    const fullName = `SCIENTIFIC_WORKBENCH.${schema}.${table}`
    setSelectedTable(fullName)
    setLoadingTable(true)
    try {
      const [colRes, dataRes] = await Promise.all([
        fetch("/api/query", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ query: "column_info", params: { schema, table } }) }),
        fetch("/api/query", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ query: "table_preview", params: { schema, table } }) }),
      ])
      const colData = await colRes.json()
      const sData = await dataRes.json()
      const cols = toRows<ColumnInfo>(colData)
      const rows = toRows<Record<string, unknown>>(sData)
      setColumns(cols)
      setSampleData(rows)
      setDetail("Data Profiling", <DataProfilingPanel table={`${schema}.${table}`} columns={cols} />)
    } catch {
      setColumns([])
      setSampleData([])
    }
    setLoadingTable(false)
  }, [setDetail])

  // Auto-select table from ?table= query param
  useEffect(() => {
    if (tableParam && !loadingSchemas) {
      const parts = tableParam.split(".")
      if (parts.length === 3) {
        setExpandedSchema(parts[1])
        selectTable(parts[1], parts[2])
      }
    }
  }, [tableParam, loadingSchemas, selectTable])

  const filteredSchemas = schemas.map((s) => ({
    ...s,
    tables: s.tables.filter((t) => !searchFilter || t.toLowerCase().includes(searchFilter.toLowerCase()) || s.schema.toLowerCase().includes(searchFilter.toLowerCase())),
  })).filter((s) => s.tables.length > 0)

  return (
    <div style={{ display: "flex", gap: 0, height: "calc(100vh - 48px)" }}>
      {/* Schema tree */}
      <div style={{ width: 260, minWidth: 260, borderRight: "1px solid var(--sf-border)", background: "var(--sf-card-bg)", display: "flex", flexDirection: "column", overflow: "hidden" }}>
        <div style={{ padding: "12px", borderBottom: "1px solid var(--sf-border)" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 6, padding: "6px 10px", borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)" }}>
            <Search size={14} style={{ color: "var(--sf-text-muted)" }} />
            <input
              value={searchFilter}
              onChange={(e) => setSearchFilter(e.target.value)}
              placeholder="Filter tables..."
              style={{ flex: 1, border: "none", outline: "none", background: "transparent", fontSize: 13, color: "var(--sf-text)" }}
            />
          </div>
        </div>
        <div style={{ flex: 1, overflowY: "auto", padding: "8px 0" }}>
          {loadingSchemas && <div style={{ padding: 16, fontSize: 13, color: "var(--sf-text-muted)" }}>Loading schemas...</div>}
          {filteredSchemas.map((s) => (
            <div key={s.schema}>
              <button
                onClick={() => setExpandedSchema(expandedSchema === s.schema ? null : s.schema)}
                style={{ display: "flex", alignItems: "center", gap: 6, width: "100%", padding: "6px 12px", border: "none", background: "transparent", cursor: "pointer", fontSize: 12, fontWeight: 600, color: "var(--sf-text-muted)", textTransform: "uppercase", letterSpacing: "0.03em" }}
              >
                {expandedSchema === s.schema ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
                {s.schema}
                <span style={{ marginLeft: "auto", fontSize: 11, color: "var(--sf-text-subtle)" }}>{s.tables.length}</span>
              </button>
              {expandedSchema === s.schema && s.tables.map((t) => {
                const fullName = `SCIENTIFIC_WORKBENCH.${s.schema}.${t}`
                const isActive = selectedTable === fullName
                return (
                  <button
                    key={t}
                    onClick={() => selectTable(s.schema, t)}
                    style={{
                      display: "flex", alignItems: "center", gap: 8, width: "100%",
                      padding: "5px 12px 5px 28px", border: "none", cursor: "pointer",
                      fontSize: 13, color: isActive ? "var(--sf-blue)" : "var(--sf-text)",
                      background: isActive ? "var(--role-info-bg)" : "transparent",
                      borderRadius: "var(--radius-xs)", margin: "1px 4px", transition: "background 0.1s",
                    }}
                    onMouseEnter={(e) => { if (!isActive) e.currentTarget.style.background = "var(--sf-surface-2)" }}
                    onMouseLeave={(e) => { if (!isActive) e.currentTarget.style.background = isActive ? "var(--role-info-bg)" : "transparent" }}
                  >
                    <Table2 size={14} style={{ flexShrink: 0 }} />
                    <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{t}</span>
                  </button>
                )
              })}
            </div>
          ))}
        </div>
      </div>

      {/* Table viewer */}
      <div style={{ flex: 1, overflow: "auto", padding: 24 }}>
        {!selectedTable && (
          <div style={{ textAlign: "center", paddingTop: 80, color: "var(--sf-text-muted)" }}>
            <Table2 size={48} style={{ margin: "0 auto 16px", opacity: 0.3 }} />
            <p style={{ fontSize: 14 }}>Select a table from the schema browser to view its data</p>
          </div>
        )}
        {selectedTable && (
          <>
            <div style={{ marginBottom: 16 }}>
              <h2 style={{ fontSize: 16, fontWeight: 600, color: "var(--sf-text)", marginBottom: 4 }}>{selectedTable.split(".").pop()}</h2>
              <p style={{ fontSize: 12, color: "var(--sf-text-muted)", fontFamily: "var(--font-fira-mono)" }}>{selectedTable}</p>
            </div>
            {loadingTable ? (
              <div style={{ padding: 24, textAlign: "center", color: "var(--sf-text-muted)", fontSize: 13 }}>Loading...</div>
            ) : (
              <div style={{ borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", overflow: "auto" }}>
                <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
                  <thead>
                    <tr style={{ background: "var(--sf-dark)" }}>
                      {columns.map((col) => (
                        <th key={col.COLUMN_NAME} style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)", whiteSpace: "nowrap", fontSize: 12 }}>{col.COLUMN_NAME}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {sampleData.slice(0, 50).map((row, i) => (
                      <tr key={i} style={{ borderBottom: "1px solid var(--sf-border)" }}>
                        {columns.map((col) => (
                          <td key={col.COLUMN_NAME} style={{ padding: "6px 12px", color: "var(--sf-text)", whiteSpace: "nowrap", maxWidth: 300, overflow: "hidden", textOverflow: "ellipsis" }}>
                            {String(row[col.COLUMN_NAME] ?? "")}
                          </td>
                        ))}
                      </tr>
                    ))}
                  </tbody>
                </table>
                {sampleData.length === 0 && <div style={{ padding: 24, textAlign: "center", color: "var(--sf-text-muted)", fontSize: 13 }}>No data found</div>}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}
