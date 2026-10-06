"use client"

import { useState, useRef, useEffect, useCallback } from "react"
import { useDetailPanel } from "@/components/detail-panel-context"
import { MarkdownContent } from "@/components/markdown-content"
import { Send, MessageSquare, Sparkles, Plus, Trash2, Loader2 } from "lucide-react"

interface Message {
  role: "user" | "agent"
  content: string
  timestamp: string
}

interface ChatSession {
  SESSION_ID: string
  TITLE: string
  UPDATED_AT: string
}

function ThinkingIndicator() {
  const [elapsed, setElapsed] = useState(0)
  useEffect(() => {
    const t = setInterval(() => setElapsed((s) => s + 1), 1000)
    return () => clearInterval(t)
  }, [])
  const phase = elapsed < 5 ? "Connecting to agent..." : elapsed < 15 ? "Analyzing your question..." : elapsed < 30 ? "Querying data and tools..." : elapsed < 60 ? "Processing results..." : "Still working — complex queries take longer..."
  return (
    <div style={{ display: "flex", alignItems: "flex-start", gap: 8, marginBottom: 12 }}>
      <div style={{ width: 28, height: 28, borderRadius: "var(--radius-pill)", background: "var(--role-info-bg)", display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
        <Loader2 size={14} style={{ color: "var(--sf-blue)", animation: "spin 1.2s linear infinite" }} />
      </div>
      <div style={{ padding: "10px 14px", borderRadius: "var(--radius-lg)", background: "var(--sf-card-bg)", border: "1px solid var(--sf-border)", minWidth: 200 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 4 }}>
          <div style={{ display: "flex", gap: 3 }}>
            <span style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--sf-blue)", animation: "pulse 1.4s ease-in-out infinite" }} />
            <span style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--sf-blue)", animation: "pulse 1.4s ease-in-out 0.2s infinite" }} />
            <span style={{ width: 6, height: 6, borderRadius: "50%", background: "var(--sf-blue)", animation: "pulse 1.4s ease-in-out 0.4s infinite" }} />
          </div>
          <span style={{ fontSize: 11, color: "var(--sf-text-muted)", fontFamily: "var(--font-fira-mono)" }}>{elapsed}s</span>
        </div>
        <div style={{ fontSize: 13, color: "var(--sf-text-muted)" }}>{phase}</div>
      </div>
      <style>{`
        @keyframes spin { to { transform: rotate(360deg) } }
        @keyframes pulse { 0%,100% { opacity: 0.3 } 50% { opacity: 1 } }
      `}</style>
    </div>
  )
}

function ChatHistoryPanel({
  sessions, activeId, onSelect, onNewChat, onDelete,
}: {
  sessions: ChatSession[]; activeId: string | null
  onSelect: (s: ChatSession) => void; onNewChat: () => void; onDelete: (id: string) => void
}) {
  return (
    <div className="space-y-2">
      <button
        onClick={onNewChat}
        style={{
          display: "flex", alignItems: "center", gap: 6, width: "100%",
          padding: "8px 12px", borderRadius: "var(--radius-sm)",
          border: "1px dashed var(--sf-border)", background: "transparent",
          cursor: "pointer", fontSize: 13, fontWeight: 500, color: "var(--sf-blue)",
        }}
      >
        <Plus size={14} /> New Chat
      </button>
      {sessions.map((s) => {
        const isActive = s.SESSION_ID === activeId
        return (
          <div key={s.SESSION_ID} style={{
            display: "flex", alignItems: "center", gap: 4, padding: "8px 12px",
            borderRadius: "var(--radius-sm)",
            border: `1px solid ${isActive ? "var(--sf-blue)" : "var(--sf-border)"}`,
            background: isActive ? "var(--role-info-bg)" : "var(--sf-card-bg)",
            cursor: "pointer",
          }}>
            <div style={{ flex: 1, minWidth: 0 }} onClick={() => onSelect(s)}>
              <div style={{ fontSize: 13, fontWeight: 500, color: "var(--sf-text)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{s.TITLE}</div>
              <div style={{ fontSize: 11, color: "var(--sf-text-muted)" }}>{s.UPDATED_AT ? new Date(s.UPDATED_AT).toLocaleDateString() : ""}</div>
            </div>
            <button
              onClick={(e) => { e.stopPropagation(); onDelete(s.SESSION_ID) }}
              style={{ background: "transparent", border: "none", padding: 4, cursor: "pointer", color: "var(--sf-text-muted)", flexShrink: 0 }}
            >
              <Trash2 size={13} />
            </button>
          </div>
        )
      })}
    </div>
  )
}

export default function ChatPage() {
  const [messages, setMessages] = useState<Message[]>([])
  const [input, setInput] = useState("")
  const [loading, setLoading] = useState(false)
  const [sessions, setSessions] = useState<ChatSession[]>([])
  const [threadId, setThreadId] = useState<string | null>(null)
  const [parentMessageId, setParentMessageId] = useState<string | null>(null)
  const { setDetail } = useDetailPanel()
  const bottomRef = useRef<HTMLDivElement>(null)

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: "smooth" }) }, [messages])

  const loadSessions = useCallback(async () => {
    try {
      const res = await fetch("/api/chat/sessions")
      const data = await res.json()
      setSessions((data.sessions || []) as ChatSession[])
    } catch { /* empty */ }
  }, [])

  useEffect(() => { loadSessions() }, [loadSessions])

  useEffect(() => {
    setDetail("Chat History", (
      <ChatHistoryPanel
        sessions={sessions} activeId={threadId}
        onSelect={loadSession} onNewChat={startNewChat} onDelete={deleteSession}
      />
    ))
  }, [sessions, threadId, setDetail])

  async function loadSession(session: ChatSession) {
    setThreadId(session.SESSION_ID)
    setMessages([])
    try {
      const res = await fetch(`/api/chat/sessions/${session.SESSION_ID}`)
      const data = await res.json()
      setMessages((data.messages || []) as Message[])
    } catch { /* empty */ }
  }

  function startNewChat() {
    setMessages([])
    setThreadId(null)
    setParentMessageId(null)
  }

  async function deleteSession(id: string) {
    try {
      await fetch(`/api/chat/sessions/${id}`, { method: "DELETE" })
      if (threadId === id) { setMessages([]); setThreadId(null); setParentMessageId(null) }
      loadSessions()
    } catch { /* empty */ }
  }

  async function sendMessage() {
    if (!input.trim() || loading) return
    const userMsg = input.trim()
    setInput("")
    setMessages((prev) => [...prev, { role: "user", content: userMsg, timestamp: new Date().toISOString() }])
    setLoading(true)

    try {
      const res = await fetch("/api/agent", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: userMsg, thread_id: threadId, parent_message_id: parentMessageId }),
      })
      const data = await res.json()

      // Capture thread_id and parent_message_id for continuity
      const newThreadId = data.thread_id
      if (newThreadId && !threadId) {
        setThreadId(newThreadId)
        // Save session metadata (first message only)
        const title = userMsg.length > 60 ? userMsg.slice(0, 60) + "..." : userMsg
        fetch("/api/chat/sessions", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title, thread_id: newThreadId }),
        }).then(() => loadSessions())
      } else if (threadId) {
        // Update timestamp on existing session
        fetch(`/api/chat/sessions/${threadId}`, {
          method: "PUT",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({}),
        }).then(() => loadSessions())
      }

      // Track parent_message_id for next turn
      if (data.parent_message_id) {
        setParentMessageId(data.parent_message_id)
      }

      const content = data.response || data.error || "No response received."
      setMessages((prev) => [...prev, { role: "agent", content, timestamp: new Date().toISOString() }])
    } catch {
      setMessages((prev) => [...prev, { role: "agent", content: "An error occurred. Please try again.", timestamp: new Date().toISOString() }])
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "calc(100vh - 48px)", maxWidth: 800, margin: "0 auto" }}>
      <div style={{ flex: 1, overflowY: "auto", padding: "24px 0" }}>
        {messages.length === 0 && (
          <div style={{ textAlign: "center", paddingTop: 80 }}>
            <div style={{ width: 56, height: 56, borderRadius: "var(--radius-lg)", background: "var(--role-info-bg)", display: "inline-flex", alignItems: "center", justifyContent: "center", marginBottom: 16 }}>
              <Sparkles size={28} style={{ color: "var(--sf-blue)" }} />
            </div>
            <h2 style={{ fontSize: 20, fontWeight: 600, color: "var(--sf-text)", marginBottom: 8 }}>Scientific Discovery Agent</h2>
            <p style={{ fontSize: 14, color: "var(--sf-text-muted)", maxWidth: 480, margin: "0 auto", lineHeight: 1.6 }}>
              Ask me to analyze data, run computational tools, execute workflows, or explore your scientific assets.
            </p>
          </div>
        )}
        {messages.map((m, i) => (
          <div key={i} style={{ display: "flex", justifyContent: m.role === "user" ? "flex-end" : "flex-start", marginBottom: 12 }}>
            {m.role === "agent" && (
              <div style={{ width: 28, height: 28, borderRadius: "var(--radius-pill)", background: "var(--role-info-bg)", display: "flex", alignItems: "center", justifyContent: "center", marginRight: 8, flexShrink: 0, marginTop: 2 }}>
                <Sparkles size={14} style={{ color: "var(--sf-blue)" }} />
              </div>
            )}
            <div style={{
              maxWidth: "75%", padding: "10px 14px", borderRadius: "var(--radius-lg)",
              ...(m.role === "user"
                ? { background: "var(--sf-primary)", color: "#fff", fontSize: 14, lineHeight: 1.6 }
                : { background: "var(--sf-card-bg)", border: "1px solid var(--sf-border)" }),
            }}>
              {m.role === "user" ? (
                <p style={{ margin: 0, whiteSpace: "pre-wrap" }}>{m.content}</p>
              ) : (
                <MarkdownContent content={m.content} />
              )}
            </div>
          </div>
        ))}
        {loading && <ThinkingIndicator />}
        <div ref={bottomRef} />
      </div>

      <div style={{ padding: "16px 0", borderTop: "1px solid var(--sf-border)" }}>
        <div style={{ display: "flex", gap: 8, alignItems: "center", padding: "8px 12px", borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)" }}>
          <MessageSquare size={18} style={{ color: "var(--sf-text-muted)", flexShrink: 0 }} />
          <input
            value={input} onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && !e.shiftKey && sendMessage()}
            placeholder="Ask the Discovery Agent..."
            disabled={loading}
            style={{ flex: 1, border: "none", outline: "none", background: "transparent", fontSize: 14, color: "var(--sf-text)" }}
          />
          <button onClick={sendMessage} disabled={loading || !input.trim()} style={{
            width: 32, height: 32, borderRadius: "var(--radius-sm)", border: "none",
            background: input.trim() ? "var(--sf-primary)" : "var(--sf-surface-2)",
            color: input.trim() ? "#fff" : "var(--sf-text-muted)",
            display: "flex", alignItems: "center", justifyContent: "center", cursor: "pointer",
          }}>
            <Send size={16} />
          </button>
        </div>
      </div>
    </div>
  )
}
