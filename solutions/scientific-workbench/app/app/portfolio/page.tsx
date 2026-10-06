"use client"

import { useState, useEffect } from "react"
import { useDetailPanel } from "@/components/detail-panel-context"
import { DetailPanelEmpty } from "@/components/detail-panel-empty"
import { Briefcase, Target, TrendingUp, Pause, AlertTriangle } from "lucide-react"

interface Program {
  name: string
  target: string
  status: string
  phase: string
  efficacy: number
  enrichment: number
  safety: number
}

function ScoreBadge({ score, label }: { score: number; label: string }) {
  const color = score >= 70 ? "var(--role-success)" : score >= 40 ? "var(--role-caution)" : "var(--role-critical)"
  const bg = score >= 70 ? "var(--role-success-bg)" : score >= 40 ? "var(--role-caution-bg)" : "var(--role-critical-bg)"
  return (
    <span style={{ fontSize: 11, fontWeight: 500, padding: "2px 8px", borderRadius: "var(--radius-xs)", color, background: bg }}>
      {label} {score}
    </span>
  )
}

function ProgramDetailPanel({ program }: { program: Program }) {
  return (
    <div className="space-y-4">
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Program</div>
        <div style={{ fontSize: 14, fontWeight: 500, color: "var(--sf-text)" }}>{program.name}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Target</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{program.target}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Phase</div>
        <div style={{ fontSize: 13, color: "var(--sf-text)" }}>{program.phase}</div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 8, textTransform: "uppercase" }}>Scores</div>
        {/* Simple radar-style score display */}
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 8 }}>
          {[
            { label: "Efficacy", value: program.efficacy },
            { label: "Enrichment", value: program.enrichment },
            { label: "Safety", value: program.safety },
          ].map((s) => (
            <div key={s.label} style={{ textAlign: "center", padding: 12, borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)" }}>
              <div style={{ fontSize: 20, fontWeight: 600, color: s.value >= 70 ? "var(--role-success)" : s.value >= 40 ? "var(--role-caution)" : "var(--role-critical)" }}>{s.value}</div>
              <div style={{ fontSize: 11, color: "var(--sf-text-muted)", marginTop: 2 }}>{s.label}</div>
            </div>
          ))}
        </div>
      </div>
      <div>
        <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Status</div>
        <span style={{
          fontSize: 12, fontWeight: 500, padding: "2px 8px", borderRadius: "var(--radius-xs)",
          color: program.status === "Active" ? "var(--role-success)" : program.status === "Paused" ? "var(--role-caution)" : "var(--sf-text-muted)",
          background: program.status === "Active" ? "var(--role-success-bg)" : program.status === "Paused" ? "var(--role-caution-bg)" : "var(--sf-surface-2)",
        }}>
          {program.status}
        </span>
      </div>
    </div>
  )
}

const SAMPLE_PROGRAMS: Program[] = [
  { name: "KRAS-G12C Binders", target: "KRAS", status: "Active", phase: "Hit-to-Lead", efficacy: 82, enrichment: 75, safety: 68 },
  { name: "PD-L1 Nanobodies", target: "PD-L1", status: "Active", phase: "Lead Optimization", efficacy: 71, enrichment: 88, safety: 79 },
  { name: "CDK4/6 Degraders", target: "CDK4", status: "Active", phase: "Target Validation", efficacy: 55, enrichment: 62, safety: 90 },
  { name: "EGFR-T790M Rescue", target: "EGFR", status: "Active", phase: "Hit Generation", efficacy: 45, enrichment: 50, safety: 72 },
  { name: "TNF-α Bispecifics", target: "TNF-α", status: "Paused", phase: "Lead Optimization", efficacy: 60, enrichment: 43, safety: 35 },
]

function KpiCard({ icon: Icon, value, label, color }: { icon: typeof Briefcase; value: number | string; label: string; color: string }) {
  return (
    <div style={{ padding: 16, borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)", display: "flex", alignItems: "center", gap: 12 }}>
      <div style={{ width: 40, height: 40, borderRadius: "var(--radius-sm)", background: color + "1a", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <Icon size={20} style={{ color }} />
      </div>
      <div>
        <div style={{ fontSize: 22, fontWeight: 600, color: "var(--sf-text)" }}>{value}</div>
        <div style={{ fontSize: 12, color: "var(--sf-text-muted)" }}>{label}</div>
      </div>
    </div>
  )
}

export default function PortfolioPage() {
  const [programs, setPrograms] = useState<Program[]>(SAMPLE_PROGRAMS)
  const { setDetail } = useDetailPanel()

  useEffect(() => {
    setDetail("Program Details", <DetailPanelEmpty icon={<Briefcase size={32} />} message="Select a program from the table to view its scores and details." />)
  }, [setDetail])

  const active = programs.filter((p) => p.status === "Active").length
  const strongSignal = programs.filter((p) => p.efficacy >= 70 && p.enrichment >= 70).length
  const paused = programs.filter((p) => p.status === "Paused").length
  const targets = new Set(programs.map((p) => p.target)).size

  return (
    <div>
      <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)", marginBottom: 20 }}>Portfolio</h1>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 12, marginBottom: 24 }}>
        <KpiCard icon={Briefcase} value={active} label="Active Programs" color="#2365d1" />
        <KpiCard icon={TrendingUp} value={strongSignal} label="Strong Signal" color="#1f8b4c" />
        <KpiCard icon={Pause} value={paused} label="Paused" color="#9a6700" />
        <KpiCard icon={Target} value={targets} label="Unique Targets" color="#7c3aed" />
      </div>

      <div style={{ borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", overflow: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
          <thead>
            <tr style={{ background: "var(--sf-dark)" }}>
              <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Program</th>
              <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Target</th>
              <th style={{ padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Phase</th>
              <th style={{ padding: "8px 12px", textAlign: "center", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Eff</th>
              <th style={{ padding: "8px 12px", textAlign: "center", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Enr</th>
              <th style={{ padding: "8px 12px", textAlign: "center", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Saf</th>
              <th style={{ padding: "8px 12px", textAlign: "center", fontWeight: 600, fontSize: 12, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>Status</th>
            </tr>
          </thead>
          <tbody>
            {programs.map((p, i) => (
              <tr
                key={i}
                onClick={() => setDetail("Program Details", <ProgramDetailPanel program={p} />)}
                style={{ borderBottom: "1px solid var(--sf-border)", cursor: "pointer", transition: "background 0.1s" }}
                onMouseEnter={(e) => (e.currentTarget.style.background = "var(--sf-surface-2)")}
                onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
              >
                <td style={{ padding: "8px 12px", fontWeight: 500, color: "var(--sf-text)" }}>{p.name}</td>
                <td style={{ padding: "8px 12px", fontFamily: "var(--font-fira-mono)", fontSize: 12, color: "var(--sf-text-muted)" }}>{p.target}</td>
                <td style={{ padding: "8px 12px", color: "var(--sf-text-muted)" }}>{p.phase}</td>
                <td style={{ padding: "8px 12px", textAlign: "center" }}><ScoreBadge score={p.efficacy} label="Eff" /></td>
                <td style={{ padding: "8px 12px", textAlign: "center" }}><ScoreBadge score={p.enrichment} label="Enr" /></td>
                <td style={{ padding: "8px 12px", textAlign: "center" }}><ScoreBadge score={p.safety} label="Saf" /></td>
                <td style={{ padding: "8px 12px", textAlign: "center" }}>
                  <span style={{
                    fontSize: 12, fontWeight: 500, padding: "2px 8px", borderRadius: "var(--radius-xs)",
                    color: p.status === "Active" ? "var(--role-success)" : "var(--role-caution)",
                    background: p.status === "Active" ? "var(--role-success-bg)" : "var(--role-caution-bg)",
                  }}>
                    {p.status}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
