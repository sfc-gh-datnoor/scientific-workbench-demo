"use client"

import { useState } from "react"
import { AppSidebar } from "@/components/app-sidebar"
import { AgentPanel } from "@/components/agent-panel"
import { DetailPanel } from "@/components/detail-panel"
import { DetailPanelProvider } from "@/components/detail-panel-context"

export function AppShell({ children }: { children: React.ReactNode }) {
  const [agentOpen, setAgentOpen] = useState(false)

  return (
    <DetailPanelProvider>
      <div className="flex h-screen overflow-hidden">
        <AppSidebar
          onToggleAgent={() => setAgentOpen((o) => !o)}
          agentOpen={agentOpen}
        />
        <div
          className="flex flex-1 overflow-hidden"
          style={{
            marginRight: "var(--agent-content-shift, 0px)",
            transition: "margin-right 0.15s ease",
          }}
        >
          <main className="flex-1 overflow-y-auto" style={{ padding: 24, background: "var(--sf-bg)" }}>
            {children}
          </main>
          <DetailPanel />
        </div>
        <AgentPanel open={agentOpen} onClose={() => setAgentOpen(false)} />
      </div>
    </DetailPanelProvider>
  )
}
