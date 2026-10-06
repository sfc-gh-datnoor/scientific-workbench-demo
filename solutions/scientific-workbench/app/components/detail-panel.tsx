"use client"

import { useDetailPanel } from "@/components/detail-panel-context"
import { X } from "lucide-react"

export function DetailPanel() {
  const { state, clearDetail } = useDetailPanel()

  if (!state.open) return null

  return (
    <aside
      style={{
        width: 320,
        minWidth: 320,
        borderLeft: "1px solid var(--sf-border)",
        background: "var(--sf-card-bg)",
        display: "flex",
        flexDirection: "column",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "12px 16px",
          borderBottom: "1px solid var(--sf-border)",
          background: "var(--sf-dark)",
        }}
      >
        <h2 style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text)", margin: 0 }}>
          {state.title}
        </h2>
        <button
          onClick={clearDetail}
          aria-label="Close detail panel"
          style={{
            background: "transparent",
            border: "none",
            borderRadius: "var(--radius-sm)",
            padding: 4,
            color: "var(--sf-text-muted)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <X size={16} />
        </button>
      </div>
      <div style={{ flex: 1, overflowY: "auto", padding: 16 }}>
        {state.content}
      </div>
    </aside>
  )
}
