"use client"

import { useState, useEffect, useCallback } from "react"
import { useRouter } from "next/navigation"
import { useDetailPanel } from "@/components/detail-panel-context"
import { DetailPanelEmpty } from "@/components/detail-panel-empty"
import { FlaskConical, Clock, CheckCircle, XCircle, Loader2, Table2, ChevronDown, ChevronRight } from "lucide-react"
import { toRows } from "@/lib/query-rows"

interface Experiment {
  RUN_ID: string
  TEMPLATE_ID: string
  TEMPLATE_NAME: string | null
  STATUS: string
  STARTED_AT: string
  COMPLETED_AT: string | null
  PARAMETERS: string | Record<string, unknown>
  AGENT_SUMMARY: string | null
  STEP_RESULTS: string | unknown[] | null
}

interface ResultRow {
  [key: string]: unknown
}

function StatusBadge({ status }: { status: string }) {
  const s = status?.toUpperCase()
  const config = s === "COMPLETED" || s === "SUCCESS"
    ? { icon: CheckCircle, color: "var(--role-success)", bg: "var(--role-success-bg)" }
    : s === "FAILED" || s === "ERROR"
    ? { icon: XCircle, color: "var(--role-critical)", bg: "var(--role-critical-bg)" }
    : s === "PARTIAL"
    ? { icon: Clock, color: "var(--role-caution)", bg: "var(--role-caution-bg)" }
    : s === "RUNNING"
    ? { icon: Loader2, color: "var(--sf-blue)", bg: "var(--role-info-bg)" }
    : { icon: Clock, color: "var(--role-caution)", bg: "var(--role-caution-bg)" }
  const Icon = config.icon
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 4, fontSize: 12, fontWeight: 500, padding: "2px 8px", borderRadius: "var(--radius-xs)", color: config.color, background: config.bg }}>
      <Icon size={12} /> {status}
    </span>
  )
}

function ResultsTable({ rows, columns }: { rows: ResultRow[]; columns: string[] }) {
  if (rows.length === 0) return <div style={{ fontSize: 12, color: "var(--sf-text-muted)", padding: "8px 0" }}>No result rows found.</div>

  const sciMetrics = ["PLDDT", "IPAE", "SCRMSD", "IPTM", "CONFIDENCE", "BINDING_AFFINITY", "SCORE", "ENERGY"]
  const metricCols = columns.filter((c) => sciMetrics.some((m) => c.toUpperCase().includes(m)))
  const displayCols = columns.slice(0, 8)

  return (
    <div style={{ borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", overflow: "auto", maxHeight: 300 }}>
      <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 11 }}>
        <thead>
          <tr style={{ background: "var(--sf-dark)" }}>
            {displayCols.map((col) => (
              <th key={col} style={{ padding: "6px 8px", textAlign: "left", fontWeight: 600, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)", whiteSpace: "nowrap", fontSize: 11 }}>{col}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.slice(0, 20).map((row, i) => (
            <tr key={i} style={{ borderBottom: "1px solid var(--sf-border)" }}>
              {displayCols.map((col) => {
                const val = row[col]
                const isMetric = metricCols.includes(col)
                const numVal = typeof val === "number" ? val : parseFloat(String(val))
                return (
                  <td key={col} style={{ padding: "4px 8px", color: "var(--sf-text)", whiteSpace: "nowrap", maxWidth: 160, overflow: "hidden", textOverflow: "ellipsis" }}>
                    {isMetric && !isNaN(numVal) ? (
                      <span style={{
                        fontSize: 11, fontWeight: 500, padding: "1px 5px", borderRadius: "var(--radius-xs)",
                        color: numVal > 0.8 ? "var(--role-success)" : numVal > 0.5 ? "var(--role-caution)" : "var(--role-critical)",
                        background: numVal > 0.8 ? "var(--role-success-bg)" : numVal > 0.5 ? "var(--role-caution-bg)" : "var(--role-critical-bg)",
                      }}>
                        {numVal.toFixed(3)}
                      </span>
                    ) : (
                      String(val ?? "")
                    )}
                  </td>
                )
              })}
            </tr>
          ))}
        </tbody>
      </table>
      {rows.length > 20 && <div style={{ padding: "6px 8px", fontSize: 11, color: "var(--sf-text-muted)", background: "var(--sf-dark)" }}>Showing 20 of {rows.length} rows</div>}
    </div>
  )
}

function ExperimentDetailPanel({ exp }: { exp: Experiment }) {
  const [resultRows, setResultRows] = useState<ResultRow[]>([])
  const [resultColumns, setResultColumns] = useState<string[]>([])
  const [loadingResults, setLoadingResults] = useState(false)
  const [resultsExpanded, setResultsExpanded] = useState(false)
  const [resultError, setResultError] = useState<string | null>(null)

  let params: Record<string, unknown> = {}
  try {
    const raw = exp.PARAMETERS
    params = typeof raw === "string" ? JSON.parse(raw || "{}") : (raw as Record<string, unknown>) ?? {}
  } catch { /* empty */ }

  const outputTable = (params.output_table as string | undefined)

  const fetchResults = useCallback(async () => {
    if (!outputTable) return
    setResultsExpanded(true)
    setLoadingResults(true)
    setResultError(null)
    try {
      const res = await fetch("/api/query", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          query: "experiment_results",
          params: {
            database: outputTable.split(".")[0] || "SCIENTIFIC_WORKBENCH",
            schema: outputTable.split(".")[1] || "WORKFLOWS",
            table: outputTable.split(".").pop() || "",
          },
        }),
      })
      const data = await res.json()
      if (data.error) { setResultError(data.error); return }
      const rows = toRows<ResultRow>(data)
      setResultRows(rows)
      if (rows.length > 0) setResultColumns(Object.keys(rows[0]))
    } catch {
      setResultError("Failed to load results")
    } finally {
      setLoadingResults(false)
    }
  }, [outputTable])

  // Auto-load results when the panel opens and there is an output table
  useEffect(() => {
    if (outputTable && resultRows.length === 0) {
      fetchResults()
    }
  }, [outputTable, fetchResults, resultRows.length])

  const toggleResults = useCallback(() => {
    if (!resultsExpanded && resultRows.length === 0) {
      fetchResults()
    } else {
      setResultsExpanded((v) => !v)
    }
  }, [resultsExpanded, resultRows.length, fetchResults])

  return (
    <div className="space-y-4">
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Run ID</div>
        <div style={{ fontSize: 12, fontFamily: "var(--font-fira-mono)", color: "var(--sf-text)" }}>{exp.RUN_ID}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Template</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{exp.TEMPLATE_NAME || exp.TEMPLATE_ID}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Status</div>
        <StatusBadge status={exp.STATUS} />
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Started</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{new Date(exp.STARTED_AT).toLocaleString()}</div>
      </div>
      {exp.COMPLETED_AT && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Completed</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{new Date(exp.COMPLETED_AT).toLocaleString()}</div>
        </div>
      )}
      {Object.keys(params).length > 0 && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Parameters</div>
          <pre style={{ fontSize: 11, fontFamily: "var(--font-fira-mono)", background: "var(--sf-surface-2)", padding: 8, borderRadius: "var(--radius-sm)", overflow: "auto", maxHeight: 120 }}>
            {JSON.stringify(params, null, 2)}
          </pre>
        </div>
      )}
      {exp.AGENT_SUMMARY && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Summary</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)", lineHeight: 1.5 }}>{exp.AGENT_SUMMARY}</div>
        </div>
      )}

      {/* Step Results */}
      {(() => {
        let steps: { step: number; tool: string; ok: boolean; r?: string; err?: string; ms?: number }[] = []
        try {
          const raw = exp.STEP_RESULTS
          steps = typeof raw === "string" ? JSON.parse(raw || "[]") : (Array.isArray(raw) ? raw : [])
        } catch { /* empty */ }
        if (steps.length === 0) return null
        return (
          <div>
            <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 8, textTransform: "uppercase" }}>Step Results</div>
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              {steps.map((s, i) => (
                <div key={i} style={{ padding: "8px 10px", borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)" }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 6, marginBottom: s.ok === false && s.err ? 4 : 0 }}>
                    {s.ok ? (
                      <CheckCircle size={13} style={{ color: "var(--role-success)", flexShrink: 0 }} />
                    ) : (
                      <XCircle size={13} style={{ color: "var(--role-critical)", flexShrink: 0 }} />
                    )}
                    <span style={{ fontSize: 12, fontWeight: 500, color: "var(--sf-text)" }}>Step {s.step}: {s.tool}</span>
                    {s.ms != null && (
                      <span style={{ fontSize: 10, color: "var(--sf-text-muted)", marginLeft: "auto" }}>{(s.ms / 1000).toFixed(1)}s</span>
                    )}
                  </div>
                  {s.ok === false && s.err && (
                    <div style={{ fontSize: 11, color: "var(--role-critical)", marginTop: 4, maxHeight: 60, overflowY: "auto", fontFamily: "var(--font-fira-mono)", lineHeight: 1.4 }}>
                      {s.err.slice(0, 200)}{s.err.length > 200 ? "..." : ""}
                    </div>
                  )}
                  {s.ok && s.r && s.r.startsWith("ERROR") && (
                    <div style={{ fontSize: 11, color: "var(--role-caution)", marginTop: 4, maxHeight: 60, overflowY: "auto", lineHeight: 1.4 }}>
                      {s.r.slice(0, 200)}{s.r.length > 200 ? "..." : ""}
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        )
      })()}

      {/* Results section */}
      <div style={{ borderTop: "1px solid var(--sf-border)", paddingTop: 12 }}>
        {outputTable ? (
          <>
            <button
              onClick={toggleResults}
              style={{
                display: "flex", alignItems: "center", gap: 6, width: "100%",
                padding: "8px 0", border: "none", background: "transparent",
                cursor: "pointer", fontSize: 13, fontWeight: 600, color: "var(--sf-text)",
              }}
            >
              {resultsExpanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
              <Table2 size={14} style={{ color: "var(--sf-blue)" }} />
              Results
              <span style={{ fontSize: 11, fontWeight: 400, color: "var(--sf-text-muted)", marginLeft: "auto" }}>{outputTable.split(".").pop()}</span>
            </button>
            {resultsExpanded && (
              <div style={{ marginTop: 8 }}>
                {loadingResults && <div style={{ fontSize: 12, color: "var(--sf-text-muted)", padding: 8 }}>Loading results...</div>}
                {resultError && <div style={{ fontSize: 12, color: "var(--role-critical)", padding: 8 }}>{resultError}</div>}
                {!loadingResults && !resultError && resultRows.length > 0 && (
                  <ResultsTable rows={resultRows} columns={resultColumns} />
                )}
                {!loadingResults && !resultError && resultRows.length === 0 && !loadingResults && (
                  <div style={{ fontSize: 12, color: "var(--sf-text-muted)", padding: 8 }}>No result data found in {outputTable}</div>
                )}
              </div>
            )}
          </>
        ) : (
          <div style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 12, color: "var(--sf-text-muted)" }}>
            <Table2 size={14} />
            No output table associated with this run
          </div>
        )}
      </div>
    </div>
  )
}

export default function ExperimentsPage() {
  const [experiments, setExperiments] = useState<Experiment[]>([])
  const [loading, setLoading] = useState(true)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const { setDetail } = useDetailPanel()
  const router = useRouter()

  useEffect(() => {
    setDetail("Experiment Details", <DetailPanelEmpty icon={<FlaskConical size={32} />} message="Select an experiment to view its details, parameters, and results." />)
  }, [setDetail])

  useEffect(() => {
    async function load() {
      try {
        const res = await fetch("/api/query", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query: "experiments_list" }),
        })
        const data = await res.json()
        // Guard: a failed query returns a JSON error object, not an array.
        setExperiments(toRows<Experiment>(data))
      } catch { setExperiments([]) }
      setLoading(false)
    }
    load()
  }, [])

  function selectExperiment(exp: Experiment) {
    setSelectedId(exp.RUN_ID)
    setDetail("Experiment Details", <ExperimentDetailPanel exp={exp} />)
  }

  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)" }}>Experiments</h1>
        <span style={{ fontSize: 13, color: "var(--sf-text-muted)" }}>{experiments.length} runs</span>
      </div>

      {loading ? (
        <div style={{ padding: 40, textAlign: "center", color: "var(--sf-text-muted)" }}>Loading experiments...</div>
      ) : experiments.length === 0 ? (
        <div style={{ padding: 60, textAlign: "center", color: "var(--sf-text-muted)" }}>
          <FlaskConical size={48} style={{ margin: "0 auto 12px", opacity: 0.3 }} />
          <p style={{ fontSize: 14 }}>No experiments yet. Run a workflow template to create one.</p>
        </div>
      ) : (
        <div style={{ borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", overflow: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
            <thead>
              <tr style={{ background: "var(--sf-dark)" }}>
                <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Run ID</th>
                <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Template</th>
                <th style={{ padding: "8px 12px", textAlign: "center", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Status</th>
                <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Started</th>
                <th style={{ padding: "8px 12px", textAlign: "center", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Results</th>
              </tr>
            </thead>
            <tbody>
              {experiments.map((exp) => {
                const isSelected = selectedId === exp.RUN_ID
                const hasOutput = (() => { try { const raw = exp.PARAMETERS; const p = typeof raw === "string" ? JSON.parse(raw || "{}") : (raw ?? {}); return ((p as Record<string, unknown>).output_table as string) || null } catch { return null } })()
                return (
                  <tr
                    key={exp.RUN_ID}
                    onClick={() => selectExperiment(exp)}
                    style={{
                      borderBottom: "1px solid var(--sf-border)", cursor: "pointer", transition: "background 0.1s",
                      background: isSelected ? "var(--role-info-bg)" : "transparent",
                    }}
                    onMouseEnter={(e) => { if (!isSelected) e.currentTarget.style.background = "var(--sf-surface-2)" }}
                    onMouseLeave={(e) => { if (!isSelected) e.currentTarget.style.background = "transparent" }}
                  >
                    <td style={{ padding: "8px 12px", fontFamily: "var(--font-fira-mono)", fontSize: 12, color: "var(--sf-text-muted)" }}>{exp.RUN_ID.slice(0, 8)}...</td>
                    <td style={{ padding: "8px 12px", fontWeight: 500, color: "var(--sf-text)" }}>{exp.TEMPLATE_NAME || exp.TEMPLATE_ID}</td>
                    <td style={{ padding: "8px 12px", textAlign: "center" }}><StatusBadge status={exp.STATUS} /></td>
                    <td style={{ padding: "8px 12px", color: "var(--sf-text-muted)" }}>{new Date(exp.STARTED_AT).toLocaleString()}</td>
                    <td style={{ padding: "8px 12px", textAlign: "center" }}>
                      {hasOutput ? (
                        <a
                          href={`/explore?table=${hasOutput}`}
                          onClick={(e) => { e.stopPropagation(); router.push(`/explore?table=${hasOutput}`) }}
                          style={{ display: "inline-flex", alignItems: "center", gap: 3, fontSize: 11, color: "var(--sf-blue)", textDecoration: "none", fontWeight: 500 }}
                        >
                          <Table2 size={12} /> View
                        </a>
                      ) : (
                        <span style={{ fontSize: 11, color: "var(--sf-text-muted)" }}>—</span>
                      )}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
