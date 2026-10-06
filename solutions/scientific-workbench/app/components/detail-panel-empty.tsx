"use client"

interface Props {
  icon?: React.ReactNode
  message: string
}

export function DetailPanelEmpty({ icon, message }: Props) {
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", padding: "40px 16px", textAlign: "center" }}>
      {icon && <div style={{ marginBottom: 12, opacity: 0.3 }}>{icon}</div>}
      <p style={{ fontSize: 13, color: "var(--sf-text-muted)", lineHeight: 1.5, margin: 0 }}>{message}</p>
    </div>
  )
}
