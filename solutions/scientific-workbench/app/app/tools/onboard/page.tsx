"use client"

import { useState, useRef, useEffect } from "react"
import { useRouter } from "next/navigation"
import { ArrowLeft, Send, Loader2, Check, Package, Globe, Code, Database, Server, GitBranch } from "lucide-react"

interface Message {
  role: "user" | "assistant"
  content: string
  action?: string | null
  toolSpec?: Record<string, unknown> | null
  submitResult?: Record<string, unknown> | null
}

const STARTERS = [
  { icon: Package, text: "Add a Python package as a tool", color: "#7c3aed" },
  { icon: Globe, text: "Connect an external REST API", color: "#0097a7" },
  { icon: Database, text: "Register an existing Snowflake procedure", color: "#2365d1" },
  { icon: Code, text: "Create a custom Python function", color: "#1f8b4c" },
  { icon: Server, text: "Deploy a container tool on SPCS", color: "#c5331f" },
  { icon: GitBranch, text: "Import a tool from a Git repository", color: "#9a6700" },
]

function ToolPreviewCard({ spec, onConfirm }: { spec: Record<string, unknown>; onConfirm: () => void }) {
  const params = spec.parameters as Record<string, Record<string, unknown>> | undefined
  return (
    <div style={{ margin: "8px 0", padding: 16, borderRadius: "var(--radius-md)", border: "1.5px solid var(--sf-blue)", background: "var(--role-info-bg)" }}>
      <div style={{ fontSize: 12, fontWeight: 600, color: "var(--sf-blue)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 8 }}>Tool Preview</div>
      <div style={{ display: "grid", gridTemplateColumns: "110px 1fr", gap: "4px 12px", fontSize: 13 }}>
        <span style={{ color: "var(--sf-text-muted)" }}>Name:</span>
        <span style={{ fontFamily: "var(--font-fira-mono)", color: "var(--sf-text)" }}>{spec.name as string}</span>
        <span style={{ color: "var(--sf-text-muted)" }}>Display:</span>
        <span style={{ color: "var(--sf-text)" }}>{spec.display_name as string}</span>
        <span style={{ color: "var(--sf-text-muted)" }}>Source:</span>
        <span style={{ color: "var(--sf-text)" }}>{String(spec.source_type).replace(/_/g, " ")}</span>
        <span style={{ color: "var(--sf-text-muted)" }}>Domains:</span>
        <span style={{ color: "var(--sf-text)" }}>{Array.isArray(spec.domains) ? (spec.domains as string[]).join(", ") : String(spec.domains)}</span>
        <span style={{ color: "var(--sf-text-muted)" }}>Compute:</span>
        <span style={{ color: "var(--sf-text)" }}>{spec.compute_env as string || "warehouse"}</span>
        <span style={{ color: "var(--sf-text-muted)" }}>Visibility:</span>
        <span style={{ color: "var(--sf-text)" }}>{spec.visibility as string || "shared"}</span>
      </div>
      {!!spec.description && (
        <div style={{ fontSize: 12, color: "var(--sf-text-muted)", marginTop: 8, lineHeight: 1.5 }}>{String(spec.description)}</div>
      )}
      {params && Object.keys(params).length > 0 && (
        <div style={{ marginTop: 10 }}>
          <div style={{ fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)", marginBottom: 4, textTransform: "uppercase" }}>Parameters</div>
          <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
            {Object.entries(params).map(([k, v]) => (
              <div key={k} style={{ display: "flex", gap: 8, fontSize: 12, alignItems: "baseline" }}>
                <span style={{ fontFamily: "var(--font-fira-mono)", color: "var(--sf-text)", minWidth: 120 }}>{k}</span>
                <span style={{ color: "var(--sf-text-muted)" }}>{typeof v === "object" && v ? String((v as Record<string, unknown>).type ?? "STRING") : String(v)}</span>
                {typeof v === "object" && v && !!(v as Record<string, unknown>).semantic_type && (
                  <span style={{ fontSize: 10, padding: "1px 6px", borderRadius: 10, background: "#f0e6ff", color: "#7c3aed" }}>
                    {(v as Record<string, unknown>).semantic_type as string}
                  </span>
                )}
              </div>
            ))}
          </div>
        </div>
      )}
      {spec.source_type !== "existing_procedure" && (
        <div style={{ fontSize: 11, color: "#856404", marginTop: 8, padding: "4px 8px", background: "#fef3cd", borderRadius: "var(--radius-xs)" }}>
          Requires admin approval before activation.
        </div>
      )}
      <button onClick={onConfirm} style={{
        marginTop: 12, padding: "8px 20px", fontSize: 13, fontWeight: 500,
        borderRadius: "var(--radius-sm)", border: "none", background: "var(--sf-blue)",
        color: "#fff", cursor: "pointer", display: "inline-flex", alignItems: "center", gap: 6,
      }}>
        <Check size={14} /> Confirm & Submit
      </button>
    </div>
  )
}

function SubmitResultCard({ result }: { result: Record<string, unknown> }) {
  const isError = result.status === "ERROR"
  return (
    <div style={{
      margin: "8px 0", padding: 16, borderRadius: "var(--radius-md)",
      border: `1.5px solid ${isError ? "#ef5350" : "var(--sf-green)"}`,
      background: isError ? "#fdecea" : "var(--role-success-bg)",
    }}>
      <div style={{ fontSize: 14, fontWeight: 600, color: isError ? "#c62828" : "var(--sf-green)", marginBottom: 6 }}>
        {isError ? "Submission Failed" : result.status === "active" ? "Tool Registered" : "Submitted for Approval"}
      </div>
      <div style={{ fontSize: 13, color: "var(--sf-text)" }}>
        {isError
          ? String(result.error)
          : result.status === "active"
            ? `Tool "${result.name}" is now active and available in the workbench.`
            : `Submission ${result.submission_id} is pending admin review.`}
      </div>
    </div>
  )
}

export default function OnboardAgentPage() {
  const router = useRouter()
  const [messages, setMessages] = useState<Message[]>([])
  const [input, setInput] = useState("")
  const [loading, setLoading] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [messages])

  function getHistory(): { role: string; content: string }[] {
    return messages.map(m => ({ role: m.role, content: m.content }))
  }

  async function sendMessage(text?: string) {
    const msg = (text || input).trim()
    if (!msg || loading) return
    setInput("")

    const userMsg: Message = { role: "user", content: msg }
    setMessages(prev => [...prev, userMsg])
    setLoading(true)

    try {
      const res = await fetch("/api/tools/onboard-agent", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: msg, history: getHistory() }),
      })
      const data = await res.json()

      const assistantMsg: Message = {
        role: "assistant",
        content: data.response || data.error || "I didn't get a response. Could you try rephrasing?",
        action: data.action,
        toolSpec: data.toolSpec,
        submitResult: data.submitResult,
      }
      setMessages(prev => [...prev, assistantMsg])
    } catch {
      setMessages(prev => [...prev, {
        role: "assistant",
        content: "Connection error. Please try again.",
      }])
    } finally {
      setLoading(false)
    }
  }

  function handleConfirmSubmit(spec: Record<string, unknown>) {
    const confirmMsg = `Yes, submit this tool: ${spec.display_name || spec.name}`
    sendMessage(confirmMsg)
  }

  const inputStyle: React.CSSProperties = {
    flex: 1, border: "none", outline: "none", resize: "none", background: "transparent",
    fontSize: 14, lineHeight: 1.55, color: "var(--sf-text)", fontFamily: "inherit",
    minHeight: 24, maxHeight: 160,
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "calc(100vh - 56px)", maxWidth: 800, margin: "0 auto" }}>
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", gap: 12, padding: "16px 0", flexShrink: 0 }}>
        <button onClick={() => router.push("/tools")} style={{ background: "none", border: "none", cursor: "pointer", color: "var(--sf-text-muted)", display: "flex" }}>
          <ArrowLeft size={18} />
        </button>
        <div>
          <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)", margin: 0 }}>Add Custom Tool</h1>
          <div style={{ fontSize: 12, color: "var(--sf-text-muted)" }}>
            Describe what you need and I will build the tool for you.
            <a href="/tools/onboard/wizard" style={{ marginLeft: 8, color: "var(--sf-blue)", textDecoration: "none" }}>Prefer a form?</a>
          </div>
        </div>
      </div>

      {/* Messages */}
      <div style={{ flex: 1, overflowY: "auto", padding: "0 4px", display: "flex", flexDirection: "column", gap: 14 }}>
        {messages.length === 0 && (
          <div style={{ paddingTop: 40 }}>
            <div style={{ fontSize: 22, fontWeight: 600, color: "var(--sf-text)", marginBottom: 4 }}>What tool would you like to add?</div>
            <div style={{ fontSize: 14, color: "var(--sf-text-muted)", marginBottom: 24, lineHeight: 1.5 }}>
              Tell me about a Python package, REST API, custom function, or existing procedure you want to make available in the workbench.
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8 }}>
              {STARTERS.map(s => (
                <button key={s.text} onClick={() => sendMessage(s.text)}
                  style={{
                    padding: 12, borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)",
                    background: "var(--sf-surface-1)", cursor: "pointer", textAlign: "left",
                    display: "flex", alignItems: "flex-start", gap: 10, transition: "border-color 0.12s",
                  }}
                  onMouseEnter={e => { e.currentTarget.style.borderColor = "var(--sf-blue)" }}
                  onMouseLeave={e => { e.currentTarget.style.borderColor = "var(--sf-border)" }}
                >
                  <s.icon size={16} style={{ color: s.color, marginTop: 2, flexShrink: 0 }} />
                  <span style={{ fontSize: 13, color: "var(--sf-text)", lineHeight: 1.4 }}>{s.text}</span>
                </button>
              ))}
            </div>
          </div>
        )}

        {messages.map((msg, i) => (
          <div key={i}>
            {msg.role === "user" ? (
              <div style={{
                background: "var(--sf-card-bg)", border: "1px solid var(--sf-border)",
                borderRadius: "var(--radius-md)", padding: "10px 14px",
                fontSize: 14, lineHeight: 1.55, color: "var(--sf-text)", whiteSpace: "pre-wrap",
                maxWidth: "85%", marginLeft: "auto",
              }}>
                {msg.content}
              </div>
            ) : (
              <div style={{ maxWidth: "90%" }}>
                <div style={{ fontSize: 14, lineHeight: 1.6, color: "var(--sf-text)", whiteSpace: "pre-wrap" }}>
                  {msg.content}
                </div>
                {msg.action === "preview" && msg.toolSpec && (
                  <ToolPreviewCard spec={msg.toolSpec} onConfirm={() => handleConfirmSubmit(msg.toolSpec!)} />
                )}
                {msg.action === "submitted" && msg.submitResult && (
                  <SubmitResultCard result={msg.submitResult} />
                )}
              </div>
            )}
          </div>
        ))}

        {loading && (
          <div style={{ fontSize: 13, color: "var(--sf-text-muted)", display: "flex", alignItems: "center", gap: 8 }}>
            <Loader2 size={16} className="animate-spin" /> Thinking...
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Composer */}
      <div style={{ flexShrink: 0, padding: "12px 0" }}>
        <div style={{
          display: "flex", alignItems: "end", gap: 8,
          borderRadius: "var(--radius-lg)", border: "1px solid var(--sf-border-strong)",
          padding: "10px 14px", boxShadow: "0 1px 3px rgba(16,24,40,0.06)",
        }}
          onFocus={e => { e.currentTarget.style.borderColor = "var(--sf-blue)" }}
          onBlur={e => { e.currentTarget.style.borderColor = "var(--sf-border-strong)" }}
        >
          <textarea
            ref={inputRef}
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={e => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMessage() } }}
            placeholder="Describe the tool you want to add..."
            rows={1}
            style={inputStyle}
            onInput={e => {
              const el = e.currentTarget
              el.style.height = "auto"
              el.style.height = Math.min(el.scrollHeight, 160) + "px"
            }}
          />
          <button onClick={() => sendMessage()} disabled={!input.trim() || loading}
            style={{
              background: input.trim() ? "var(--sf-blue)" : "var(--sf-surface-2)",
              color: input.trim() ? "#fff" : "var(--sf-text-muted)",
              border: "none", borderRadius: "var(--radius-sm)",
              width: 34, height: 34, display: "flex", alignItems: "center", justifyContent: "center",
              cursor: input.trim() ? "pointer" : "default", flexShrink: 0,
            }}>
            <Send size={16} />
          </button>
        </div>
      </div>
    </div>
  )
}
