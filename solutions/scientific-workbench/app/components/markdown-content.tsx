"use client"

import ReactMarkdown from "react-markdown"
import remarkGfm from "remark-gfm"
import type { Components } from "react-markdown"

const components: Components = {
  h1: ({ children }) => <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)", margin: "16px 0 8px" }}>{children}</h1>,
  h2: ({ children }) => <h2 style={{ fontSize: 16, fontWeight: 600, color: "var(--sf-text)", margin: "14px 0 6px" }}>{children}</h2>,
  h3: ({ children }) => <h3 style={{ fontSize: 14, fontWeight: 600, color: "var(--sf-text)", margin: "12px 0 4px" }}>{children}</h3>,
  p: ({ children }) => <p style={{ margin: "6px 0", lineHeight: 1.6 }}>{children}</p>,
  strong: ({ children }) => <strong style={{ fontWeight: 600 }}>{children}</strong>,
  a: ({ href, children }) => <a href={href} style={{ color: "var(--sf-blue)", textDecoration: "none" }} target="_blank" rel="noopener noreferrer">{children}</a>,
  ul: ({ children }) => <ul style={{ margin: "6px 0", paddingLeft: 20 }}>{children}</ul>,
  ol: ({ children }) => <ol style={{ margin: "6px 0", paddingLeft: 20 }}>{children}</ol>,
  li: ({ children }) => <li style={{ margin: "3px 0", lineHeight: 1.5 }}>{children}</li>,
  code: ({ className, children }) => {
    const isBlock = className?.includes("language-")
    if (isBlock) {
      return (
        <pre style={{ margin: "8px 0", padding: "10px 12px", borderRadius: "var(--radius-sm)", background: "var(--sf-surface-2)", overflow: "auto", fontSize: 12, fontFamily: "var(--font-fira-mono)", lineHeight: 1.5 }}>
          <code>{children}</code>
        </pre>
      )
    }
    return <code style={{ padding: "1px 5px", borderRadius: "var(--radius-xs)", background: "var(--sf-surface-2)", fontSize: "0.9em", fontFamily: "var(--font-fira-mono)" }}>{children}</code>
  },
  pre: ({ children }) => <>{children}</>,
  table: ({ children }) => (
    <div style={{ margin: "8px 0", borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)", overflow: "auto" }}>
      <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12 }}>{children}</table>
    </div>
  ),
  thead: ({ children }) => <thead style={{ background: "var(--sf-dark)" }}>{children}</thead>,
  th: ({ children }) => <th style={{ padding: "6px 10px", textAlign: "left", fontWeight: 600, fontSize: 11, color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)" }}>{children}</th>,
  td: ({ children }) => <td style={{ padding: "5px 10px", borderBottom: "1px solid var(--sf-border)", color: "var(--sf-text)" }}>{children}</td>,
  blockquote: ({ children }) => <blockquote style={{ margin: "8px 0", paddingLeft: 12, borderLeft: "3px solid var(--sf-blue)", color: "var(--sf-text-muted)" }}>{children}</blockquote>,
  hr: () => <hr style={{ border: "none", borderTop: "1px solid var(--sf-border)", margin: "12px 0" }} />,
}

export function MarkdownContent({ content }: { content: string }) {
  return (
    <div style={{ fontSize: 14, lineHeight: 1.6, color: "var(--sf-text)" }}>
      <ReactMarkdown remarkPlugins={[remarkGfm]} components={components}>
        {content}
      </ReactMarkdown>
    </div>
  )
}
