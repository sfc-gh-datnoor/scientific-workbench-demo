"use client"

import { useState, useEffect } from "react"
import { useRouter } from "next/navigation"
import { ArrowLeft, Check, X, Clock, Loader2 } from "lucide-react"

interface Submission {
  SUBMISSION_ID: string
  TOOL_SPEC: Record<string, unknown> | string
  SUBMITTED_BY: string
  SUBMITTED_AT: string
  STATUS: string
  REVIEWER: string | null
  REVIEWED_AT: string | null
  REVIEW_NOTES: string | null
  TOOL_ID: string | null
}

export default function SubmissionsPage() {
  const router = useRouter()
  const [submissions, setSubmissions] = useState<Submission[]>([])
  const [loading, setLoading] = useState(true)
  const [actionLoading, setActionLoading] = useState<string | null>(null)
  const [notes, setNotes] = useState<Record<string, string>>({})

  async function fetchSubmissions() {
    try {
      const res = await fetch("/api/tools/submissions")
      const data = await res.json()
      setSubmissions(data.submissions || [])
    } catch { /* empty */ }
    setLoading(false)
  }

  useEffect(() => { fetchSubmissions() }, [])

  async function handleAction(submissionId: string, action: "approve" | "reject") {
    setActionLoading(submissionId)
    try {
      const res = await fetch("/api/tools/submissions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ submission_id: submissionId, action, notes: notes[submissionId] || "" }),
      })
      if (res.ok) {
        await fetchSubmissions()
      }
    } catch { /* empty */ }
    setActionLoading(null)
  }

  function parseSpec(spec: Record<string, unknown> | string): Record<string, unknown> {
    if (typeof spec === "string") {
      try { return JSON.parse(spec) } catch { return {} }
    }
    return spec || {}
  }

  const statusBadge = (status: string) => {
    const styles: Record<string, { bg: string; color: string; icon: React.ReactNode }> = {
      pending: { bg: "#fef3cd", color: "#856404", icon: <Clock size={12} /> },
      approved: { bg: "var(--role-success-bg)", color: "var(--sf-green)", icon: <Check size={12} /> },
      rejected: { bg: "#fdecea", color: "#c62828", icon: <X size={12} /> },
    }
    const s = styles[status] || styles.pending
    return (
      <span style={{ fontSize: 11, padding: "2px 8px", borderRadius: 20, background: s.bg, color: s.color, display: "inline-flex", alignItems: "center", gap: 4 }}>
        {s.icon} {status}
      </span>
    )
  }

  const inputStyle: React.CSSProperties = {
    width: "100%", padding: "6px 10px", fontSize: 12, borderRadius: "var(--radius-sm)",
    border: "1px solid var(--sf-border)", background: "var(--sf-surface-1)", color: "var(--sf-text)", outline: "none",
  }

  return (
    <div style={{ maxWidth: 800, margin: "0 auto" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 24 }}>
        <button onClick={() => router.push("/tools")} style={{ background: "none", border: "none", cursor: "pointer", color: "var(--sf-text-muted)", display: "flex" }}>
          <ArrowLeft size={18} />
        </button>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)", margin: 0 }}>Tool Submissions</h1>
        <span style={{ fontSize: 13, color: "var(--sf-text-muted)" }}>Admin Review Queue</span>
      </div>

      {loading ? (
        <div style={{ padding: 60, textAlign: "center", color: "var(--sf-text-muted)" }}>
          <Loader2 size={24} className="animate-spin" style={{ margin: "0 auto 12px" }} />
          <div style={{ fontSize: 13 }}>Loading submissions...</div>
        </div>
      ) : submissions.length === 0 ? (
        <div style={{ padding: 60, textAlign: "center", color: "var(--sf-text-muted)" }}>
          <div style={{ fontSize: 14 }}>No submissions found.</div>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          {submissions.map(sub => {
            const spec = parseSpec(sub.TOOL_SPEC)
            const isPending = sub.STATUS === "pending"
            return (
              <div key={sub.SUBMISSION_ID} style={{
                padding: 16, borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)",
                background: "var(--sf-card-bg)",
              }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 10 }}>
                  <div>
                    <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)" }}>
                      {(spec.display_name as string) || (spec.name as string) || sub.SUBMISSION_ID}
                    </div>
                    <div style={{ fontSize: 12, color: "var(--sf-text-muted)", marginTop: 2 }}>
                      {(spec.source_type as string || "").replace(/_/g, " ")} | Submitted by {sub.SUBMITTED_BY} | {new Date(sub.SUBMITTED_AT).toLocaleDateString()}
                    </div>
                  </div>
                  {statusBadge(sub.STATUS)}
                </div>

                {!!spec.description && (
                  <div style={{ fontSize: 12, color: "var(--sf-text-muted)", marginBottom: 10, lineHeight: 1.5 }}>
                    {String(spec.description)}
                  </div>
                )}

                <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 10 }}>
                  {Array.isArray(spec.domains) && (spec.domains as string[]).map(d => (
                    <span key={d} style={{ fontSize: 11, padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "var(--sf-surface-2)", color: "var(--sf-text-muted)" }}>{d}</span>
                  ))}
                  <span style={{ fontSize: 11, padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "var(--sf-surface-2)", color: "var(--sf-text-muted)" }}>
                    {(spec.compute_env as string) || "warehouse"}
                  </span>
                  <span style={{ fontSize: 11, padding: "2px 8px", borderRadius: "var(--radius-xs)", background: "var(--sf-surface-2)", color: "var(--sf-text-muted)" }}>
                    {(spec.visibility as string) || "shared"}
                  </span>
                </div>

                {sub.REVIEW_NOTES && (
                  <div style={{ fontSize: 12, color: "var(--sf-text)", padding: 8, background: "var(--sf-surface-1)", borderRadius: "var(--radius-xs)", marginBottom: 10 }}>
                    Review: {sub.REVIEW_NOTES} — {sub.REVIEWER}
                  </div>
                )}

                {isPending && (
                  <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                    <input style={{ ...inputStyle, flex: 1 }} placeholder="Review notes (optional)"
                      value={notes[sub.SUBMISSION_ID] || ""}
                      onChange={e => setNotes({ ...notes, [sub.SUBMISSION_ID]: e.target.value })} />
                    <button onClick={() => handleAction(sub.SUBMISSION_ID, "approve")}
                      disabled={actionLoading === sub.SUBMISSION_ID}
                      style={{
                        padding: "6px 14px", fontSize: 12, fontWeight: 500, borderRadius: "var(--radius-sm)",
                        border: "none", background: "var(--sf-green)", color: "#fff", cursor: "pointer",
                        display: "flex", alignItems: "center", gap: 4,
                      }}>
                      {actionLoading === sub.SUBMISSION_ID ? <Loader2 size={12} className="animate-spin" /> : <Check size={12} />} Approve
                    </button>
                    <button onClick={() => handleAction(sub.SUBMISSION_ID, "reject")}
                      disabled={actionLoading === sub.SUBMISSION_ID}
                      style={{
                        padding: "6px 14px", fontSize: 12, fontWeight: 500, borderRadius: "var(--radius-sm)",
                        border: "1px solid #ef5350", background: "transparent", color: "#ef5350", cursor: "pointer",
                        display: "flex", alignItems: "center", gap: 4,
                      }}>
                      <X size={12} /> Reject
                    </button>
                  </div>
                )}
              </div>
            )
          })}
        </div>
      )}
    </div>
  )
}
