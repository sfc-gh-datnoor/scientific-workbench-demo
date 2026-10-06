"use client"

import { Wrench, Clock, CheckCircle, XCircle, ChevronDown, ChevronRight } from "lucide-react"
import { useState } from "react"

export interface ToolExecution {
  tool_name: string
  tool_type?: string
  domain?: string
  description?: string
  parameters_used: Record<string, unknown>
  input_schema?: { required?: string[]; optional?: string[]; formats?: Record<string, string> }
  result?: unknown
  error?: string
  success: boolean
  execution_time_ms?: number
  call_sql?: string
}

export function ToolExecutionCard({ execution }: { execution: ToolExecution }) {
  const [showParams, setShowParams] = useState(true)
  const [showResult, setShowResult] = useState(false)

  const paramEntries = Object.entries(execution.parameters_used || {})
  const schema = execution.input_schema || {}

  return (
    <div style={{
      margin: "8px 0", borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)",
      background: "var(--sf-card-bg)", overflow: "hidden",
    }}>
      {/* Header */}
      <div style={{
        display: "flex", alignItems: "center", gap: 8, padding: "10px 14px",
        background: execution.success ? "var(--role-success-bg)" : execution.error ? "var(--role-critical-bg)" : "var(--role-info-bg)",
        borderBottom: "1px solid var(--sf-border)",
      }}>
        <Wrench size={15} style={{ color: execution.success ? "var(--role-success)" : execution.error ? "var(--role-critical)" : "var(--sf-blue)" }} />
        <span style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text)" }}>{execution.tool_name}</span>
        {execution.domain && (
          <span style={{ fontSize: 11, padding: "1px 6px", borderRadius: "var(--radius-xs)", background: "var(--sf-surface-2)", color: "var(--sf-text-muted)" }}>{execution.domain}</span>
        )}
        <span style={{ marginLeft: "auto", display: "flex", alignItems: "center", gap: 4, fontSize: 12 }}>
          {execution.success ? (
            <><CheckCircle size={13} style={{ color: "var(--role-success)" }} /> <span style={{ color: "var(--role-success)" }}>Success</span></>
          ) : execution.error ? (
            <><XCircle size={13} style={{ color: "var(--role-critical)" }} /> <span style={{ color: "var(--role-critical)" }}>Failed</span></>
          ) : (
            <><Clock size={13} style={{ color: "var(--sf-blue)" }} /> <span style={{ color: "var(--sf-blue)" }}>Running</span></>
          )}
        </span>
      </div>

      {/* Parameters */}
      {paramEntries.length > 0 && (
        <div style={{ borderBottom: "1px solid var(--sf-border)" }}>
          <button
            onClick={() => setShowParams(!showParams)}
            style={{
              display: "flex", alignItems: "center", gap: 6, width: "100%", padding: "8px 14px",
              border: "none", background: "transparent", cursor: "pointer",
              fontSize: 12, fontWeight: 600, color: "var(--sf-text-muted)", textTransform: "uppercase", letterSpacing: "0.03em",
            }}
          >
            {showParams ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
            Parameters ({paramEntries.length})
          </button>
          {showParams && (
            <div style={{ padding: "0 14px 10px" }}>
              {paramEntries.map(([key, val]) => {
                const isRequired = schema.required?.includes(key)
                const format = schema.formats?.[key]
                return (
                  <div key={key} style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", padding: "4px 0", borderBottom: "1px solid var(--sf-border)", gap: 12 }}>
                    <div>
                      <span style={{ fontSize: 12, fontFamily: "var(--font-fira-mono)", fontWeight: 500, color: "var(--sf-text)" }}>{key}</span>
                      {isRequired && <span style={{ fontSize: 10, color: "var(--role-critical)", marginLeft: 4 }}>required</span>}
                      {format && <div style={{ fontSize: 10, color: "var(--sf-text-muted)" }}>{format}</div>}
                    </div>
                    <div style={{ fontSize: 12, fontFamily: "var(--font-fira-mono)", color: "var(--sf-text-muted)", textAlign: "right", maxWidth: "60%", wordBreak: "break-all" }}>
                      {typeof val === "string" && val.length > 80 ? val.slice(0, 80) + "..." : String(val ?? "null")}
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </div>
      )}

      {/* Input Schema (if available and has required/optional) */}
      {(schema.required || schema.optional) && (
        <div style={{ padding: "8px 14px", borderBottom: "1px solid var(--sf-border)", fontSize: 12, color: "var(--sf-text-muted)" }}>
          {schema.required && <span>Required: <strong style={{ color: "var(--sf-text)" }}>{schema.required.join(", ")}</strong></span>}
          {schema.required && schema.optional && <span> | </span>}
          {schema.optional && <span>Optional: {schema.optional.join(", ")}</span>}
        </div>
      )}

      {/* Result */}
      {(execution.result || execution.error) && (
        <div>
          <button
            onClick={() => setShowResult(!showResult)}
            style={{
              display: "flex", alignItems: "center", gap: 6, width: "100%", padding: "8px 14px",
              border: "none", background: "transparent", cursor: "pointer",
              fontSize: 12, fontWeight: 600, color: "var(--sf-text-muted)", textTransform: "uppercase", letterSpacing: "0.03em",
            }}
          >
            {showResult ? <ChevronDown size={13} /> : <ChevronRight size={13} />}
            {execution.error ? "Error" : "Result"}
          </button>
          {showResult && (
            <div style={{ padding: "0 14px 10px" }}>
              {execution.error ? (
                <div style={{ fontSize: 12, color: "var(--role-critical)", fontFamily: "var(--font-fira-mono)" }}>{execution.error}</div>
              ) : (
                <pre style={{ fontSize: 11, fontFamily: "var(--font-fira-mono)", background: "var(--sf-surface-2)", padding: 8, borderRadius: "var(--radius-sm)", overflow: "auto", maxHeight: 200, margin: 0 }}>
                  {typeof execution.result === "string" ? execution.result : JSON.stringify(execution.result, null, 2)}
                </pre>
              )}
            </div>
          )}
        </div>
      )}

      {/* Footer with timing */}
      {execution.execution_time_ms != null && (
        <div style={{ display: "flex", alignItems: "center", gap: 6, padding: "6px 14px", background: "var(--sf-dark)", fontSize: 11, color: "var(--sf-text-muted)" }}>
          <Clock size={11} />
          {execution.execution_time_ms < 1000 ? `${execution.execution_time_ms}ms` : `${(execution.execution_time_ms / 1000).toFixed(1)}s`}
          {execution.call_sql && <span style={{ marginLeft: "auto", fontFamily: "var(--font-fira-mono)" }}>CALL {execution.tool_name}</span>}
        </div>
      )}
    </div>
  )
}
