"use client"

import { useState } from "react"
import Link from "next/link"
import { usePathname } from "next/navigation"
import {
  MessageSquare, Search, Package, FlaskConical, Wrench,
  GitBranch, BookOpen, Briefcase, Shield, Share2, ChevronLeft, ChevronRight, Sparkles,
} from "lucide-react"

const NAV_SECTIONS = [
  {
    label: "Main",
    items: [
      { href: "/chat", label: "Agent Chat", icon: MessageSquare },
      { href: "/explore", label: "Explore", icon: Search },
    ],
  },
  {
    label: "Science",
    items: [
      { href: "/catalog", label: "Asset Catalog", icon: Package },
      { href: "/experiments", label: "Experiments", icon: FlaskConical },
      { href: "/tools", label: "Tools", icon: Wrench },
      { href: "/workflows", label: "Workflows", icon: GitBranch },
      { href: "/notebooks", label: "Notebooks", icon: BookOpen },
    ],
  },
  {
    label: "Management",
    items: [
      { href: "/portfolio", label: "Portfolio", icon: Briefcase },
      { href: "/governance", label: "Governance", icon: Shield },
      { href: "/share", label: "Data Sharing", icon: Share2 },
    ],
  },
]

interface AppSidebarProps {
  onToggleAgent?: () => void
  agentOpen?: boolean
}

export function AppSidebar({ onToggleAgent, agentOpen }: AppSidebarProps) {
  const [collapsed, setCollapsed] = useState(false)
  const path = usePathname()
  const width = collapsed ? "var(--sidebar-width-collapsed)" : "var(--sidebar-width)"

  return (
    <aside
      style={{ width, minWidth: width, transition: "width 0.2s ease, min-width 0.2s ease" }}
      className="h-screen flex flex-col border-r border-[var(--sf-border)]"
      data-collapsed={collapsed}
    >
      <div
        className="flex items-center gap-2.5 px-3"
        style={{
          height: 56,
          background: "var(--sf-dark)",
          ...(collapsed ? { flexDirection: "column", padding: "12px 0", gap: 8, height: "auto" } : {}),
        }}
      >
        <img src="/snowflake-logo.svg" alt="" width={22} height={22} aria-hidden="true" />
        {!collapsed && (
          <h1 style={{ fontSize: 14, fontWeight: 600, color: "var(--sf-text)", letterSpacing: "-0.01em", margin: 0 }}>
            Scientific Workbench
          </h1>
        )}
        <button
          onClick={() => setCollapsed(!collapsed)}
          aria-label={collapsed ? "Expand sidebar" : "Collapse sidebar"}
          style={{
            marginLeft: collapsed ? 0 : "auto",
            background: "transparent", border: "none", borderRadius: "var(--radius-sm)",
            padding: 4, color: "#9aa4b2", display: "flex", alignItems: "center", justifyContent: "center",
            transition: "background 0.12s ease",
          }}
          onMouseEnter={(e) => (e.currentTarget.style.background = "var(--sf-surface-2)")}
          onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
        >
          {collapsed ? <ChevronRight size={18} /> : <ChevronLeft size={18} />}
        </button>
      </div>

      <nav className="flex-1 overflow-y-auto py-2" style={{ background: "var(--sf-dark)" }} aria-label="Main navigation">
        {NAV_SECTIONS.map((section) => (
          <div key={section.label} className="mb-1">
            {!collapsed && (
              <div style={{ fontSize: 11, fontWeight: 600, color: "rgb(98,108,126)", padding: "8px 12px 4px", letterSpacing: "0.04em", textTransform: "uppercase" }}>
                {section.label}
              </div>
            )}
            {section.items.map((item) => {
              const active = path === item.href || (item.href !== "/" && path.startsWith(item.href))
              const Icon = item.icon
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  aria-current={active ? "page" : undefined}
                  style={{
                    display: "flex", alignItems: "center", gap: 10,
                    height: 34, padding: collapsed ? "0 0" : "0 12px",
                    margin: "2px 8px", borderRadius: "var(--radius-sm)",
                    fontSize: 13, fontWeight: active ? 500 : 400, textDecoration: "none",
                    transition: "background 0.12s ease, color 0.12s ease",
                    justifyContent: collapsed ? "center" : "flex-start",
                    color: active ? "#2365d1" : "#23272c",
                    background: active ? "#e3efff" : "transparent",
                  }}
                  onMouseEnter={(e) => { if (!active) e.currentTarget.style.background = "var(--sf-surface-2)" }}
                  onMouseLeave={(e) => { if (!active) e.currentTarget.style.background = "transparent" }}
                  title={collapsed ? item.label : undefined}
                >
                  <Icon size={16} strokeWidth={1.75} />
                  {!collapsed && <span>{item.label}</span>}
                </Link>
              )
            })}
          </div>
        ))}
      </nav>

      <div style={{ background: "var(--sf-dark)", borderTop: "1px solid var(--sf-border)", padding: collapsed ? "8px 4px" : "8px" }}>
        {onToggleAgent && (
          <button
            onClick={onToggleAgent}
            style={{
              display: "flex", alignItems: "center", gap: 10, width: "100%",
              height: 34, padding: collapsed ? "0" : "0 12px", border: "none",
              borderRadius: "var(--radius-sm)", fontSize: 13, fontWeight: 400,
              color: agentOpen ? "#2365d1" : "#23272c",
              background: agentOpen ? "#e3efff" : "transparent",
              justifyContent: collapsed ? "center" : "flex-start",
              transition: "background 0.12s ease", cursor: "pointer",
            }}
            onMouseEnter={(e) => { if (!agentOpen) e.currentTarget.style.background = "var(--sf-surface-2)" }}
            onMouseLeave={(e) => { if (!agentOpen) e.currentTarget.style.background = "transparent" }}
            title={collapsed ? "Discovery Agent" : undefined}
          >
            <Sparkles size={16} strokeWidth={1.75} />
            {!collapsed && <span>Discovery Agent</span>}
          </button>
        )}
        <div style={{ display: "flex", alignItems: "center", gap: 10, padding: collapsed ? "4px 0" : "8px 12px 4px", justifyContent: collapsed ? "center" : "flex-start" }}>
          <div
            style={{
              width: 28, height: 28, borderRadius: "var(--radius-pill)",
              background: "var(--role-info-bg)", color: "var(--sf-blue)",
              display: "flex", alignItems: "center", justifyContent: "center",
              fontSize: 11, fontWeight: 600, flexShrink: 0,
            }}
            aria-hidden="true"
          >
            DA
          </div>
          {!collapsed && (
            <div style={{ overflow: "hidden" }}>
              <div style={{ fontSize: 13, fontWeight: 600, color: "var(--sf-text)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                Deven Atnoor
              </div>
              <div style={{ fontSize: 11, color: "var(--sf-text-subtle)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                WORKBENCH_SCIENTIST
              </div>
            </div>
          )}
        </div>
      </div>
    </aside>
  )
}
