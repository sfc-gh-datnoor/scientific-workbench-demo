"use client"

import { useState, useEffect } from "react"
import { useDetailPanel } from "@/components/detail-panel-context"
import { DetailPanelEmpty } from "@/components/detail-panel-empty"
import { Shield, ArrowRight, Database, CheckCircle, Clock, XCircle, FileText, Activity } from "lucide-react"
import { toRows } from "@/lib/query-rows"

interface PromotionEntry {
  PROMOTION_ID: string
  SOURCE_SCHEMA: string
  TARGET_SCHEMA: string
  TABLE_NAME: string
  ROW_COUNT: number
  DATA_TIMESTAMP: string
  ATTESTED_BY: string
  ATTESTED_AT: string
  STATUS: string
}

interface CanaryAssertion {
  ASSERTION_ID: string
  QUERY: string
  EXPECTED_ANSWER: string
  DOMAIN: string
  THRESHOLD: number
  ACTIVE: boolean
}

interface ProvenanceEntry {
  LOG_ID: number
  LOGGED_AT: string
  ACTION_TYPE: string
  TARGET: string
  USER_NAME: string
  INTERFACE: string
  SESSION_ID: string
  DURATION_MS: number | null
}

const SCHEMA_FLOW = [
  { name: "SANDBOX", color: "#9a6700", bg: "#fbf1da", desc: "Experimental" },
  { name: "VALIDATED", color: "#2365d1", bg: "#e3efff", desc: "Peer-reviewed" },
  { name: "PRODUCTION", color: "#1f8b4c", bg: "#e7f4ec", desc: "Approved" },
]

const SCHEMA_INVENTORY = [
  { name: "CATALOG", tables: 8, views: 3, functions: 12, stage: "PRODUCTION" },
  { name: "CHEMISTRY", tables: 5, views: 1, functions: 4, stage: "VALIDATED" },
  { name: "GENOMICS", tables: 6, views: 2, functions: 3, stage: "VALIDATED" },
  { name: "WORKFLOWS", tables: 4, views: 0, functions: 2, stage: "PRODUCTION" },
  { name: "PROVENANCE", tables: 2, views: 1, functions: 0, stage: "PRODUCTION" },
  { name: "GOVERNANCE", tables: 3, views: 0, functions: 1, stage: "PRODUCTION" },
]

function PromotionDetailPanel({ entry }: { entry: PromotionEntry }) {
  return (
    <div className="space-y-4">
      <div style={{ fontSize: 12, fontWeight: 600, color: "var(--sf-blue)", marginBottom: 8 }}>Promotion Details</div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Promotion ID</div>
        <div style={{ fontSize: 12, fontFamily: "var(--font-fira-mono)", color: "var(--sf-text)" }}>{entry.PROMOTION_ID}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Table</div>
        <div style={{ fontSize: 13, fontWeight: 500, color: "var(--sf-text)" }}>{entry.TABLE_NAME}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Path</div>
        <div style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 13 }}>
          <span style={{ padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "#fbf1da", color: "#9a6700" }}>{entry.SOURCE_SCHEMA}</span>
          <ArrowRight size={14} style={{ color: "var(--sf-text-muted)" }} />
          <span style={{ padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "#e3efff", color: "#2365d1" }}>{entry.TARGET_SCHEMA}</span>
        </div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Row Count</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{entry.ROW_COUNT?.toLocaleString()}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Status</div>
        <span style={{
          fontSize: 12, fontWeight: 500, padding: "2px 8px", borderRadius: "var(--radius-xs)",
          color: entry.STATUS === "approved" ? "var(--role-success)" : "var(--role-caution)",
          background: entry.STATUS === "approved" ? "var(--role-success-bg)" : "var(--role-caution-bg)",
        }}>{entry.STATUS}</span>
      </div>
      {entry.ATTESTED_BY && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Attested By</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{entry.ATTESTED_BY}</div>
        </div>
      )}
      {entry.ATTESTED_AT && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Attested At</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{new Date(entry.ATTESTED_AT).toLocaleString()}</div>
        </div>
      )}
    </div>
  )
}

function CanaryDetailPanel({ assertion }: { assertion: CanaryAssertion }) {
  return (
    <div className="space-y-4">
      <div style={{ fontSize: 12, fontWeight: 600, color: "var(--sf-blue)", marginBottom: 8 }}>Canary Details</div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Assertion ID</div>
        <div style={{ fontSize: 12, fontFamily: "var(--font-fira-mono)", color: "var(--sf-text)" }}>{assertion.ASSERTION_ID}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Domain</div>
        <span style={{ fontSize: 12, padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "var(--role-info-bg)", color: "var(--sf-blue)" }}>{assertion.DOMAIN}</span>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Question</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)", lineHeight: 1.5 }}>{assertion.QUERY}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Expected Answer</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)", lineHeight: 1.5 }}>{assertion.EXPECTED_ANSWER}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Threshold</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{assertion.THRESHOLD}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Active</div>
        <span style={{ fontSize: 12, color: assertion.ACTIVE ? "var(--role-success)" : "var(--sf-text-muted)" }}>{assertion.ACTIVE ? "Yes" : "No"}</span>
      </div>
    </div>
  )
}

function ActivityDetailPanel({ entry }: { entry: ProvenanceEntry }) {
  return (
    <div className="space-y-4">
      <div style={{ fontSize: 12, fontWeight: 600, color: "var(--sf-blue)", marginBottom: 8 }}>Activity Details</div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Log ID</div>
        <div style={{ fontSize: 12, fontFamily: "var(--font-fira-mono)", color: "var(--sf-text)" }}>{entry.LOG_ID}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Action</div>
        <div style={{ fontSize: 13, fontWeight: 500, color: "var(--sf-text)" }}>{entry.ACTION_TYPE}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Target</div>
        <div style={{ fontSize: 13, fontFamily: "var(--font-fira-mono)", color: "var(--sf-text)" }}>{entry.TARGET}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>User</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{entry.USER_NAME}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Interface</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{entry.INTERFACE}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Timestamp</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{new Date(entry.LOGGED_AT).toLocaleString()}</div>
      </div>
      {entry.DURATION_MS != null && (
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Duration</div>
          <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{entry.DURATION_MS}ms</div>
        </div>
      )}
    </div>
  )
}

export function GovernanceClient() {
  const [promotions, setPromotions] = useState<PromotionEntry[]>([])
  const [canaries, setCanaries] = useState<CanaryAssertion[]>([])
  const [provenance, setProvenance] = useState<ProvenanceEntry[]>([])
  const [loading, setLoading] = useState(true)
  const { setDetail } = useDetailPanel()

  useEffect(() => {
    setDetail("Audit Trail", <DetailPanelEmpty icon={<Shield size={32} />} message="Select a promotion, canary assertion, or activity entry to view details." />)
  }, [setDetail])

  useEffect(() => {
    async function load() {
      try {
        const [promRes, canRes, provRes] = await Promise.all([
          fetch("/api/query", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ query: "promotion_log" }) }),
          fetch("/api/query", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ query: "canary_assertions" }) }),
          fetch("/api/query", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ query: "provenance_log" }) }),
        ])
        const [promData, canData, provData] = await Promise.all([promRes.json(), canRes.json(), provRes.json()])
        setPromotions(toRows<PromotionEntry>(promData))
        setCanaries(toRows<CanaryAssertion>(canData))
        setProvenance(toRows<ProvenanceEntry>(provData))
      } catch { /* empty */ }
      setLoading(false)
    }
    load()
  }, [])

  return (
    <div>
      <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)", marginBottom: 24 }}>Governance</h1>

      {/* Schema Architecture */}
      <section style={{ marginBottom: 32 }}>
        <h2 style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text-muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 12 }}>Schema Architecture</h2>
        <div style={{ display: "flex", alignItems: "center", gap: 0, padding: 20, borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)" }}>
          {SCHEMA_FLOW.map((stage, i) => (
            <div key={stage.name} style={{ display: "flex", alignItems: "center" }}>
              <div style={{ padding: "16px 24px", borderRadius: "var(--radius-md)", background: stage.bg, border: `1px solid ${stage.color}33`, textAlign: "center", minWidth: 140 }}>
                <div style={{ fontSize: 14, fontWeight: 600, color: stage.color }}>{stage.name}</div>
                <div style={{ fontSize: 11, color: stage.color, opacity: 0.8, marginTop: 2 }}>{stage.desc}</div>
              </div>
              {i < SCHEMA_FLOW.length - 1 && <ArrowRight size={20} style={{ margin: "0 12px", color: "var(--sf-text-muted)" }} />}
            </div>
          ))}
        </div>
      </section>

      {/* Schema Inventory */}
      <section style={{ marginBottom: 32 }}>
        <h2 style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text-muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 12 }}>Schema Inventory</h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))", gap: 12 }}>
          {SCHEMA_INVENTORY.map((s) => {
            const stageConf = SCHEMA_FLOW.find((f) => f.name === s.stage) || SCHEMA_FLOW[0]
            return (
              <div key={s.name} style={{ padding: 16, borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)" }}>
                <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 8 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                    <Database size={14} style={{ color: "var(--sf-blue)" }} />
                    <span style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text)" }}>{s.name}</span>
                  </div>
                  <span style={{ fontSize: 10, fontWeight: 500, padding: "1px 6px", borderRadius: "var(--radius-xs)", color: stageConf.color, background: stageConf.bg }}>{s.stage}</span>
                </div>
                <div style={{ display: "flex", gap: 12, fontSize: 12, color: "var(--sf-text-muted)" }}>
                  <span>{s.tables} tables</span>
                  <span>{s.views} views</span>
                  <span>{s.functions} funcs</span>
                </div>
              </div>
            )
          })}
        </div>
      </section>

      {loading ? (
        <div style={{ padding: 40, textAlign: "center", color: "var(--sf-text-muted)" }}>Loading governance data...</div>
      ) : (
        <>
          {/* Promotion Audit Trail */}
          <section style={{ marginBottom: 32 }}>
            <h2 style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text-muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 12 }}>
              <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}><FileText size={14} /> Promotion Audit Trail ({promotions.length})</span>
            </h2>
            <div style={{ borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", overflow: "auto" }}>
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
                <thead>
                  <tr style={{ background: "var(--sf-dark)" }}>
                    <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Table</th>
                    <th style={{ padding: "8px 12px", textAlign: "center", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Path</th>
                    <th style={{ padding: "8px 12px", textAlign: "right", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Rows</th>
                    <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Attested By</th>
                    <th style={{ padding: "8px 12px", textAlign: "center", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Status</th>
                  </tr>
                </thead>
                <tbody>
                  {promotions.map((p) => (
                    <tr
                      key={p.PROMOTION_ID}
                      onClick={() => setDetail("Promotion Details", <PromotionDetailPanel entry={p} />)}
                      style={{ borderBottom: "1px solid var(--sf-border)", cursor: "pointer", transition: "background 0.1s" }}
                      onMouseEnter={(e) => (e.currentTarget.style.background = "var(--sf-surface-2)")}
                      onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
                    >
                      <td style={{ padding: "8px 12px", fontWeight: 500, color: "var(--sf-text)" }}>{p.TABLE_NAME}</td>
                      <td style={{ padding: "8px 12px", textAlign: "center" }}>
                        <span style={{ fontSize: 11, display: "inline-flex", alignItems: "center", gap: 4 }}>
                          <span style={{ padding: "1px 6px", borderRadius: "var(--radius-xs)", background: "#fbf1da", color: "#9a6700" }}>{p.SOURCE_SCHEMA}</span>
                          <ArrowRight size={12} style={{ color: "var(--sf-text-muted)" }} />
                          <span style={{ padding: "1px 6px", borderRadius: "var(--radius-xs)", background: "#e3efff", color: "#2365d1" }}>{p.TARGET_SCHEMA}</span>
                        </span>
                      </td>
                      <td style={{ padding: "8px 12px", textAlign: "right", fontFamily: "var(--font-fira-mono)", fontSize: 12, color: "var(--sf-text-muted)" }}>{p.ROW_COUNT}</td>
                      <td style={{ padding: "8px 12px", color: "var(--sf-text-muted)" }}>{p.ATTESTED_BY || "—"}</td>
                      <td style={{ padding: "8px 12px", textAlign: "center" }}>
                        <span style={{
                          fontSize: 11, fontWeight: 500, padding: "2px 8px", borderRadius: "var(--radius-xs)",
                          color: p.STATUS === "approved" ? "var(--role-success)" : "var(--role-caution)",
                          background: p.STATUS === "approved" ? "var(--role-success-bg)" : "var(--role-caution-bg)",
                          display: "inline-flex", alignItems: "center", gap: 3,
                        }}>
                          {p.STATUS === "approved" ? <CheckCircle size={10} /> : <Clock size={10} />} {p.STATUS}
                        </span>
                      </td>
                    </tr>
                  ))}
                  {promotions.length === 0 && <tr><td colSpan={5} style={{ padding: 24, textAlign: "center", color: "var(--sf-text-muted)" }}>No promotions recorded</td></tr>}
                </tbody>
              </table>
            </div>
          </section>

          {/* Canary Assertions */}
          <section style={{ marginBottom: 32 }}>
            <h2 style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text-muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 12 }}>
              <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}><Shield size={14} /> Biological Plausibility Canaries ({canaries.length})</span>
            </h2>
            <div style={{ borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", overflow: "auto" }}>
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
                <thead>
                  <tr style={{ background: "var(--sf-dark)" }}>
                    <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>ID</th>
                    <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Domain</th>
                    <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Question</th>
                    <th style={{ padding: "8px 12px", textAlign: "center", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Active</th>
                  </tr>
                </thead>
                <tbody>
                  {canaries.map((c) => (
                    <tr
                      key={c.ASSERTION_ID}
                      onClick={() => setDetail("Canary Details", <CanaryDetailPanel assertion={c} />)}
                      style={{ borderBottom: "1px solid var(--sf-border)", cursor: "pointer", transition: "background 0.1s" }}
                      onMouseEnter={(e) => (e.currentTarget.style.background = "var(--sf-surface-2)")}
                      onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
                    >
                      <td style={{ padding: "8px 12px", fontFamily: "var(--font-fira-mono)", fontSize: 12, color: "var(--sf-text-muted)" }}>{c.ASSERTION_ID}</td>
                      <td style={{ padding: "8px 12px" }}>
                        <span style={{ fontSize: 11, padding: "2px 6px", borderRadius: "var(--radius-xs)", background: "var(--role-info-bg)", color: "var(--sf-blue)" }}>{c.DOMAIN}</span>
                      </td>
                      <td style={{ padding: "8px 12px", color: "var(--sf-text)", maxWidth: 300, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{c.QUERY}</td>
                      <td style={{ padding: "8px 12px", textAlign: "center" }}>
                        {c.ACTIVE ? <CheckCircle size={14} style={{ color: "var(--role-success)" }} /> : <XCircle size={14} style={{ color: "var(--sf-text-muted)" }} />}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          {/* Provenance Activity Log */}
          <section>
            <h2 style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text-muted)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 12 }}>
              <span style={{ display: "inline-flex", alignItems: "center", gap: 6 }}><Activity size={14} /> Activity Log ({provenance.length})</span>
            </h2>
            <div style={{ borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", overflow: "auto" }}>
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
                <thead>
                  <tr style={{ background: "var(--sf-dark)" }}>
                    <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Action</th>
                    <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Target</th>
                    <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>User</th>
                    <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Timestamp</th>
                  </tr>
                </thead>
                <tbody>
                  {provenance.map((p) => (
                    <tr
                      key={p.LOG_ID}
                      onClick={() => setDetail("Activity Details", <ActivityDetailPanel entry={p} />)}
                      style={{ borderBottom: "1px solid var(--sf-border)", cursor: "pointer", transition: "background 0.1s" }}
                      onMouseEnter={(e) => (e.currentTarget.style.background = "var(--sf-surface-2)")}
                      onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
                    >
                      <td style={{ padding: "8px 12px", fontWeight: 500, color: "var(--sf-text)" }}>{p.ACTION_TYPE}</td>
                      <td style={{ padding: "8px 12px", fontFamily: "var(--font-fira-mono)", fontSize: 12, color: "var(--sf-text-muted)" }}>{p.TARGET}</td>
                      <td style={{ padding: "8px 12px", color: "var(--sf-text-muted)" }}>{p.USER_NAME}</td>
                      <td style={{ padding: "8px 12px", color: "var(--sf-text-muted)", fontSize: 12 }}>{new Date(p.LOGGED_AT).toLocaleString()}</td>
                    </tr>
                  ))}
                  {provenance.length === 0 && <tr><td colSpan={4} style={{ padding: 24, textAlign: "center", color: "var(--sf-text-muted)" }}>No activity recorded</td></tr>}
                </tbody>
              </table>
            </div>
          </section>
        </>
      )}
    </div>
  )
}
