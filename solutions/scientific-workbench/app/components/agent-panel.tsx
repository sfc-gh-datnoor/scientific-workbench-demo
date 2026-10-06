"use client"

import { useState, useRef, useEffect, useCallback } from "react"
import { List, Plus, PanelRightClose, Send } from "lucide-react"

interface Message {
  role: "user" | "assistant"
  content: string
  toolCalls?: string[]
}

interface AgentPanelProps {
  open: boolean
  onClose: () => void
}

const MIN_WIDTH = 340
const MAX_WIDTH = 760
const DEFAULT_WIDTH = 440
const STORAGE_KEY = "agentWidth"

export function AgentPanel({ open, onClose }: AgentPanelProps) {
  const [width, setWidth] = useState(() => {
    if (typeof window === "undefined") return DEFAULT_WIDTH
    const stored = localStorage.getItem(STORAGE_KEY)
    return stored ? Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, Number(stored))) : DEFAULT_WIDTH
  })
  const [messages, setMessages] = useState<Message[]>([])
  const [input, setInput] = useState("")
  const [loading, setLoading] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)
  const resizing = useRef(false)

  useEffect(() => {
    document.documentElement.style.setProperty(
      "--agent-content-shift",
      open ? `${width}px` : "0px"
    )
    return () => {
      document.documentElement.style.setProperty("--agent-content-shift", "0px")
    }
  }, [open, width])

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [messages])

  useEffect(() => {
    if (open) inputRef.current?.focus()
  }, [open])

  const onResizeStart = useCallback((e: React.MouseEvent) => {
    e.preventDefault()
    resizing.current = true
    document.body.style.userSelect = "none"
    document.body.style.cursor = "col-resize"

    const onMove = (ev: MouseEvent) => {
      if (!resizing.current) return
      const newWidth = Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, window.innerWidth - ev.clientX))
      setWidth(newWidth)
      localStorage.setItem(STORAGE_KEY, String(newWidth))
    }
    const onUp = () => {
      resizing.current = false
      document.body.style.userSelect = ""
      document.body.style.cursor = ""
      document.removeEventListener("mousemove", onMove)
      document.removeEventListener("mouseup", onUp)
    }
    document.addEventListener("mousemove", onMove)
    document.addEventListener("mouseup", onUp)
  }, [])

  const sendMessage = async () => {
    const text = input.trim()
    if (!text || loading) return
    setInput("")
    setMessages((prev) => [...prev, { role: "user", content: text }])
    setLoading(true)

    try {
      const res = await fetch("/api/agent", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: text }),
      })
      const data = await res.json()
      setMessages((prev) => [
        ...prev,
        { role: "assistant", content: data.response || data.error || "No response", toolCalls: data.tool_calls },
      ])
    } catch {
      setMessages((prev) => [...prev, { role: "assistant", content: "Connection error. Please try again." }])
    } finally {
      setLoading(false)
    }
  }

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      sendMessage()
    }
  }

  const startNewChat = () => {
    setMessages([])
    setInput("")
    inputRef.current?.focus()
  }

  if (!open) return null

  return (
    <div
      className="fixed top-0 right-0 bottom-0 flex flex-col"
      style={{
        width, zIndex: 60,
        borderLeft: "1px solid var(--sf-border)",
        background: "var(--sf-card-bg)",
        boxShadow: "-2px 0 8px rgba(16,24,40,0.06)",
      }}
    >
      {/* Resize handle */}
      <div
        onMouseDown={onResizeStart}
        style={{
          position: "absolute", left: -4, top: 0, bottom: 0, width: 8,
          cursor: "col-resize", background: "transparent", zIndex: 1,
        }}
      />

      {/* Header */}
      <div
        className="flex items-center justify-between px-3"
        style={{ height: 48, borderBottom: "1px solid var(--sf-border)", flexShrink: 0 }}
      >
        <button
          className="flex items-center gap-1.5"
          style={{ background: "none", border: "none", fontSize: 13, fontWeight: 550, color: "var(--sf-text)" }}
        >
          <List size={16} strokeWidth={1.75} />
          All chats
        </button>
        <div className="flex items-center gap-1">
          <IconBtn icon={Plus} label="New chat" onClick={startNewChat} />
          <IconBtn icon={PanelRightClose} label="Close panel" onClick={onClose} />
        </div>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-4" style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        {messages.length === 0 && (
          <div className="flex flex-col items-start pt-8">
            <div style={{ fontSize: 26, fontWeight: 600, lineHeight: 1.15, color: "var(--sf-text)" }}>
              Hi,
            </div>
            <div style={{ fontSize: 26, fontWeight: 600, lineHeight: 1.15, color: "var(--sf-text-subtle)", marginTop: 4 }}>
              How can I help?
            </div>
            <button
              onClick={() => inputRef.current?.focus()}
              style={{
                marginTop: 24, padding: "6px 16px", borderRadius: "var(--radius-pill)",
                border: "1px solid var(--sf-primary)", color: "var(--sf-primary)",
                background: "var(--sf-card-bg)", fontSize: 14, fontWeight: 500, cursor: "pointer",
              }}
            >
              Ask the Discovery Agent
            </button>
          </div>
        )}

        {messages.map((msg, i) => (
          <div key={i}>
            {msg.role === "user" ? (
              <div
                style={{
                  background: "var(--sf-card-bg)", border: "1px solid var(--sf-border)",
                  borderRadius: "var(--radius-md)", padding: "10px 12px",
                  fontSize: 14, lineHeight: 1.55, color: "var(--sf-text)", whiteSpace: "pre-wrap",
                }}
              >
                <span className="sr-only">You: </span>
                {msg.content}
              </div>
            ) : (
              <div style={{ fontSize: 14, lineHeight: 1.55, color: "var(--sf-text)" }}>
                {msg.content}
                {msg.toolCalls && msg.toolCalls.length > 0 && (
                  <div style={{ marginTop: 8, display: "flex", flexWrap: "wrap", gap: 4 }}>
                    {msg.toolCalls.map((tc, j) => (
                      <span
                        key={j}
                        style={{
                          fontSize: 12, padding: "2px 8px", borderRadius: "var(--radius-sm)",
                          background: "var(--sf-surface-2)", border: "1px solid var(--sf-border)",
                          fontFamily: "var(--font-fira-mono), monospace",
                        }}
                      >
                        {tc}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>
        ))}

        {loading && (
          <div style={{ fontSize: 13, color: "var(--sf-text-subtle)" }} aria-hidden="true">
            <img src="/snowflake-logo.svg" alt="" width={20} height={20} className="sf-loader-logo inline mr-2" />
            Thinking...
          </div>
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* Composer */}
      <div
        className="px-3 pb-3"
        style={{ flexShrink: 0 }}
      >
        <div
          className="flex items-end gap-2"
          style={{
            borderRadius: "var(--radius-lg)", border: "1px solid var(--sf-border-strong)",
            padding: "8px 12px",
            boxShadow: "0 1px 3px rgba(16,24,40,0.06)",
            transition: "border-color 0.12s ease",
          }}
          onFocus={(e) => (e.currentTarget.style.borderColor = "var(--sf-primary)")}
          onBlur={(e) => (e.currentTarget.style.borderColor = "var(--sf-border-strong)")}
        >
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Ask a question..."
            aria-label="Message to Discovery Agent"
            rows={1}
            style={{
              flex: 1, border: "none", outline: "none", resize: "none", background: "transparent",
              fontSize: 14, lineHeight: 1.55, color: "var(--sf-text)", fontFamily: "inherit",
              minHeight: 24, maxHeight: 120,
            }}
            onInput={(e) => {
              const el = e.currentTarget
              el.style.height = "auto"
              el.style.height = Math.min(el.scrollHeight, 120) + "px"
            }}
          />
          <button
            onClick={sendMessage}
            disabled={!input.trim() || loading}
            aria-label="Send message"
            style={{
              background: input.trim() ? "var(--sf-primary)" : "var(--sf-surface-2)",
              color: input.trim() ? "#fff" : "var(--sf-text-subtle)",
              border: "none", borderRadius: "var(--radius-sm)",
              width: 30, height: 30, display: "flex", alignItems: "center", justifyContent: "center",
              cursor: input.trim() ? "pointer" : "default", flexShrink: 0,
              transition: "background 0.12s ease",
            }}
          >
            <Send size={16} strokeWidth={1.75} />
          </button>
        </div>
      </div>
    </div>
  )
}

function IconBtn({ icon: Icon, label, onClick }: { icon: typeof Plus; label: string; onClick?: () => void }) {
  return (
    <button
      onClick={onClick}
      aria-label={label}
      style={{
        width: 30, height: 30, display: "flex", alignItems: "center", justifyContent: "center",
        background: "transparent", border: "none", borderRadius: "var(--radius-pill)",
        color: "var(--sf-text-muted)", transition: "background 0.12s ease", cursor: "pointer",
      }}
      onMouseEnter={(e) => (e.currentTarget.style.background = "var(--sf-surface-2)")}
      onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
    >
      <Icon size={16} strokeWidth={1.75} />
    </button>
  )
}
