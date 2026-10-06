"use client"

import { useCallback, useEffect, useState } from "react"
import type { CSSProperties } from "react"
import { Share2, Table2, Users, Building2, Search } from "lucide-react"

type Row = Record<string, unknown>
interface TableRow { name: string; rows: number | null; bytes: number | null }
interface RoleRow { name: string; comment: string | null }

interface StatusMessage { kind: "success" | "error"; text: string; lines?: string[] }

const cardStyle: CSSProperties = {
  padding: 20, borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)",
  background: "var(--sf-card-bg)", display: "flex", flexDirection: "column", gap: 12,
}
const labelStyle: CSSProperties = {
  display: "block", fontSize: 11, fontWeight: 600, color: "var(--sf-text-muted)",
  marginBottom: 4, textTransform: "uppercase",
}
const fieldStyle: CSSProperties = {
  width: "100%", padding: "6px 10px", borderRadius: "var(--radius-sm)",
  border: "1px solid var(--sf-border)", background: "var(--sf-card-bg)",
  fontSize: 13, color: "var(--sf-text)",
}
const thStyle: CSSProperties = {
  padding: "8px 12px", textAlign: "left", fontWeight: 600, fontSize: 12,
  color: "var(--sf-text)", borderBottom: "1px solid var(--sf-border)",
}
const tdStyle: CSSProperties = {
  padding: "6px 12px", fontSize: 13, color: "var(--sf-text)", whiteSpace: "nowrap",
  maxWidth: 300, overflow: "hidden", textOverflow: "ellipsis",
}

function actionButtonStyle(disabled: boolean): CSSProperties {
  return {
    display: "flex", alignItems: "center", justifyContent: "center", gap: 6,
    padding: "7px 14px", borderRadius: "var(--radius-sm)", border: "1px solid transparent",
    background: disabled ? "var(--sf-surface-2)" : "var(--sf-blue)",
    color: disabled ? "var(--sf-text-subtle)" : "#fff",
    fontSize: 13, fontWeight: 600, cursor: disabled ? "not-allowed" : "pointer",
  }
}

function formatRows(value: number | null): string {
  return value === null ? "—" : value.toLocaleString()
}

function formatBytes(value: number | null): string {
  if (value === null) return "—"
  let bytes = value
  const units = ["B", "KB", "MB", "GB", "TB"]
  let unit = 0
  while (bytes >= 1024 && unit < units.length - 1) { bytes /= 1024; unit++ }
  return `${unit === 0 || bytes >= 10 ? Math.round(bytes) : bytes.toFixed(1)} ${units[unit]}`
}

function pickField(row: Row, keys: string[]): string {
  for (const key of keys) {
    const v = row[key]
    if (typeof v === "string" && v.trim()) return v.trim()
    if (typeof v === "number" && Number.isFinite(v)) return String(v)
  }
  return "—"
}

function errorMessage(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback
}

async function fetchApi(action: string, params: Record<string, string> = {}): Promise<Row[]> {
  const search = new URLSearchParams({ action, ...params })
  const res = await fetch(`/api/share?${search}`)
  if (!res.ok) {
    const data = await res.json().catch(() => ({}))
    throw new Error((data as Row).error as string || `Request failed (${res.status})`)
  }
  const data = await res.json()
  return (data.rows ?? []) as Row[]
}

async function postApi(body: Record<string, string>): Promise<Row> {
  const res = await fetch("/api/share", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  })
  const data = await res.json()
  if (!res.ok) throw new Error((data as Row).error as string || `Request failed (${res.status})`)
  return data as Row
}

function StatusBanner({ status }: { status: StatusMessage }) {
  const success = status.kind === "success"
  return (
    <div style={{
      padding: "8px 10px", borderRadius: "var(--radius-sm)", fontSize: 12, lineHeight: 1.5,
      color: success ? "#1f8b4c" : "#c5331f",
      background: success ? "#e7f4ec" : "#fbeae7",
    }}>
      <div style={{ fontWeight: 600 }}>{status.text}</div>
      {status.lines && status.lines.length > 0 && (
        <ol style={{ margin: "6px 0 0", paddingLeft: 18, fontFamily: "var(--font-fira-mono)", fontSize: 11 }}>
          {status.lines.map((line, i) => <li key={i} style={{ marginBottom: 2 }}>{line}</li>)}
        </ol>
      )}
    </div>
  )
}

function stepLine(entry: unknown): string {
  if (typeof entry === "string") return entry
  if (!entry || typeof entry !== "object") return String(entry)
  const r = entry as Row
  const label = typeof r.step === "string" ? r.step : null
  const result = r.result
  let statusText: string | null = null
  if (Array.isArray(result)) {
    for (const row of result) {
      if (row && typeof row === "object" && typeof (row as Row).status === "string") {
        statusText = ((row as Row).status as string).trim()
        break
      }
    }
  }
  if (label && statusText) return `${label} — ${statusText}`
  return label ?? JSON.stringify(entry)
}

export default function SharePage() {
  const [databases, setDatabases] = useState<string[]>([])
  const [schemas, setSchemas] = useState<string[]>([])
  const [tables, setTables] = useState<TableRow[]>([])
  const [roles, setRoles] = useState<RoleRow[]>([])

  const [selectedDb, setSelectedDb] = useState("")
  const [selectedSchema, setSelectedSchema] = useState("")
  const [selectedTableName, setSelectedTableName] = useState("")

  const [pickerError, setPickerError] = useState<string | null>(null)
  const [loadingSchemas, setLoadingSchemas] = useState(false)
  const [loadingTables, setLoadingTables] = useState(false)

  const [grantRole, setGrantRole] = useState("")
  const [colleague, setColleague] = useState("")
  const [colleagueRoles, setColleagueRoles] = useState<string[] | null>(null)
  const [lookingUp, setLookingUp] = useState(false)
  const [granting, setGranting] = useState(false)
  const [grantStatus, setGrantStatus] = useState<StatusMessage | null>(null)

  const [shareName, setShareName] = useState("")
  const [targetAccount, setTargetAccount] = useState("")
  const [creating, setCreating] = useState(false)
  const [createStatus, setCreateStatus] = useState<StatusMessage | null>(null)

  const [existingShares, setExistingShares] = useState<Row[]>([])
  const [loadingShares, setLoadingShares] = useState(true)
  const [sharesError, setSharesError] = useState<string | null>(null)

  const loadShares = useCallback(async () => {
    setLoadingShares(true)
    setSharesError(null)
    try {
      setExistingShares(await fetchApi("shares"))
    } catch (error) {
      setExistingShares([])
      setSharesError(errorMessage(error, "Could not load existing shares"))
    }
    setLoadingShares(false)
  }, [])

  useEffect(() => {
    async function load() {
      try {
        const rows = await fetchApi("databases")
        setDatabases(rows.map((r) => r.name as string))
      } catch (error) {
        setDatabases([])
        setPickerError(errorMessage(error, "Could not load databases"))
      }
      try {
        const rows = await fetchApi("roles")
        setRoles(rows.map((r) => ({ name: r.name as string, comment: (r.comment as string) ?? "" })))
      } catch { setRoles([]) }
    }
    load()
    loadShares()
  }, [loadShares])

  useEffect(() => {
    setSchemas([]); setSelectedSchema("")
    if (!selectedDb) return
    let active = true
    setLoadingSchemas(true)
    fetchApi("schemas", { db: selectedDb })
      .then((rows) => { if (active) setSchemas(rows.map((r) => r.name as string)) })
      .catch((error) => { if (active) { setSchemas([]); setPickerError(errorMessage(error, "Could not load schemas")) } })
      .finally(() => { if (active) setLoadingSchemas(false) })
    return () => { active = false }
  }, [selectedDb])

  useEffect(() => {
    setTables([]); setSelectedTableName("")
    if (!selectedDb || !selectedSchema) return
    let active = true
    setLoadingTables(true)
    fetchApi("tables", { db: selectedDb, schema: selectedSchema })
      .then((rows) => { if (active) setTables(rows.map((r) => ({ name: r.name as string, rows: r.rows as number | null, bytes: r.bytes as number | null }))) })
      .catch((error) => { if (active) { setTables([]); setPickerError(errorMessage(error, "Could not load tables")) } })
      .finally(() => { if (active) setLoadingTables(false) })
    return () => { active = false }
  }, [selectedDb, selectedSchema])

  const findColleagueRoles = useCallback(async () => {
    const username = colleague.trim()
    if (!username) return
    setLookingUp(true); setGrantStatus(null)
    try {
      const rows = await fetchApi("user-roles", { username })
      const names = rows.map((r) => (r.role as string) ?? "").filter(Boolean)
      setColleagueRoles(names)
      if (names.length === 0) setGrantStatus({ kind: "error", text: `No roles found for ${username}` })
    } catch (error) {
      setColleagueRoles(null)
      setGrantStatus({ kind: "error", text: errorMessage(error, "Role lookup failed") })
    }
    setLookingUp(false)
  }, [colleague])

  const submitGrant = useCallback(async () => {
    if (!selectedDb || !selectedSchema || !selectedTableName || !grantRole.trim()) return
    setGranting(true); setGrantStatus(null)
    try {
      const data = await postApi({ action: "grant", database: selectedDb, schema: selectedSchema, table: selectedTableName, role: grantRole.trim() })
      setGrantStatus({ kind: "success", text: (data.message as string) || "Grant applied" })
    } catch (error) {
      setGrantStatus({ kind: "error", text: errorMessage(error, "Grant failed") })
    }
    setGranting(false)
  }, [selectedDb, selectedSchema, selectedTableName, grantRole])

  const submitShare = useCallback(async () => {
    if (!selectedDb || !selectedSchema || !selectedTableName || !shareName.trim() || !targetAccount.trim()) return
    setCreating(true); setCreateStatus(null)
    try {
      const data = await postApi({
        action: "create", share_name: shareName.trim(), database: selectedDb,
        table_schema: selectedSchema, table_name: selectedTableName, target_account: targetAccount.trim(),
      })
      const steps = data.steps as unknown[]
      setCreateStatus({
        kind: "success",
        text: (data.message as string) || "Share created",
        lines: Array.isArray(steps) ? steps.map(stepLine) : undefined,
      })
      await loadShares()
    } catch (error) {
      setCreateStatus({ kind: "error", text: errorMessage(error, "Share creation failed") })
    }
    setCreating(false)
  }, [selectedDb, selectedSchema, selectedTableName, shareName, targetAccount, loadShares])

  const tableChosen = Boolean(selectedDb && selectedSchema && selectedTableName)
  const grantDisabled = !tableChosen || !grantRole.trim() || granting
  const createDisabled = !tableChosen || !shareName.trim() || !targetAccount.trim() || creating

  return (
    <div>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 20 }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: "var(--sf-text)" }}>Data Sharing</h1>
        <span style={{ fontSize: 13, color: "var(--sf-text-muted)" }}>
          {tableChosen ? `${selectedDb}.${selectedSchema}.${selectedTableName}` : "No table selected"}
        </span>
      </div>

      {/* Table picker */}
      <div style={{ ...cardStyle, marginBottom: 16 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <Table2 size={16} style={{ color: "var(--sf-blue)" }} />
          <h2 style={{ fontSize: 14, fontWeight: 600, color: "var(--sf-text)", margin: 0 }}>Pick a table</h2>
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: 12 }}>
          <div>
            <label htmlFor="share-db" style={labelStyle}>Database</label>
            <select id="share-db" value={selectedDb} onChange={(e) => setSelectedDb(e.target.value)} style={fieldStyle}>
              <option value="">Select a database</option>
              {databases.map((n) => <option key={n} value={n}>{n}</option>)}
            </select>
          </div>
          <div>
            <label htmlFor="share-schema" style={labelStyle}>Schema</label>
            <select id="share-schema" value={selectedSchema} onChange={(e) => setSelectedSchema(e.target.value)} disabled={!selectedDb || loadingSchemas} style={fieldStyle}>
              <option value="">{loadingSchemas ? "Loading schemas..." : "Select a schema"}</option>
              {schemas.map((n) => <option key={n} value={n}>{n}</option>)}
            </select>
          </div>
          <div>
            <label htmlFor="share-table" style={labelStyle}>Table</label>
            <select id="share-table" value={selectedTableName} onChange={(e) => setSelectedTableName(e.target.value)} disabled={!selectedSchema || loadingTables} style={fieldStyle}>
              <option value="">{loadingTables ? "Loading tables..." : "Select a table"}</option>
              {tables.map((t) => <option key={t.name} value={t.name}>{t.name}</option>)}
            </select>
          </div>
        </div>
        {selectedTableName && tables.length > 0 && (() => {
          const t = tables.find((x) => x.name === selectedTableName)
          return t ? (
            <div style={{ display: "flex", gap: 16, fontSize: 12, color: "var(--sf-text-muted)" }}>
              <span>Rows: {formatRows(t.rows)}</span>
              <span>Size: {formatBytes(t.bytes)}</span>
            </div>
          ) : null
        })()}
        {pickerError && <StatusBanner status={{ kind: "error", text: pickerError }} />}
      </div>

      {/* Grant + Create share cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(340px, 1fr))", gap: 16, marginBottom: 16 }}>
        {/* Share with colleague */}
        <div style={cardStyle}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <Users size={16} style={{ color: "var(--sf-blue)" }} />
            <h2 style={{ fontSize: 14, fontWeight: 600, color: "var(--sf-text)", margin: 0 }}>Share with a colleague</h2>
          </div>
          <p style={{ fontSize: 12, color: "var(--sf-text-muted)", lineHeight: 1.5, margin: 0 }}>
            Grants SELECT on the selected table to a role in this account.
          </p>
          <div>
            <label htmlFor="share-role" style={labelStyle}>Role</label>
            <input id="share-role" list="share-role-options" value={grantRole} onChange={(e) => setGrantRole(e.target.value)} placeholder="Search or type a role name" style={fieldStyle} />
            <datalist id="share-role-options">
              {roles.map((r) => <option key={r.name} value={r.name}>{r.comment ?? ""}</option>)}
            </datalist>
          </div>
          <div>
            <label htmlFor="share-colleague" style={labelStyle}>Or look up a colleague&apos;s roles</label>
            <div style={{ display: "flex", gap: 8 }}>
              <input id="share-colleague" value={colleague} onChange={(e) => setColleague(e.target.value)} placeholder="Username" style={fieldStyle} />
              <button type="button" onClick={findColleagueRoles} disabled={!colleague.trim() || lookingUp} style={{
                display: "flex", alignItems: "center", gap: 6, padding: "6px 12px", whiteSpace: "nowrap",
                borderRadius: "var(--radius-sm)", border: "1px solid var(--sf-border)",
                background: "var(--sf-card-bg)", fontSize: 13, color: "var(--sf-text)",
                cursor: !colleague.trim() || lookingUp ? "not-allowed" : "pointer",
              }}>
                <Search size={14} />
                {lookingUp ? "Finding..." : "Find their roles"}
              </button>
            </div>
          </div>
          {colleagueRoles && colleagueRoles.length > 0 && (
            <div>
              <div style={labelStyle}>Roles granted to {colleague.trim()}</div>
              <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                {colleagueRoles.map((name) => {
                  const active = grantRole === name
                  return (
                    <button key={name} type="button" onClick={() => setGrantRole(name)} style={{
                      padding: "3px 10px", borderRadius: "var(--radius-pill)", cursor: "pointer",
                      border: `1px solid ${active ? "var(--sf-blue)" : "var(--sf-border)"}`,
                      background: active ? "#e3efff" : "var(--sf-surface-2)",
                      color: active ? "var(--sf-blue)" : "var(--sf-text-muted)",
                      fontSize: 11, fontFamily: "var(--font-fira-mono)",
                    }}>
                      {name}
                    </button>
                  )
                })}
              </div>
            </div>
          )}
          <button type="button" onClick={submitGrant} disabled={grantDisabled} style={actionButtonStyle(grantDisabled)}>
            {granting ? "Granting..." : "Grant SELECT"}
          </button>
          {grantStatus && <StatusBanner status={grantStatus} />}
        </div>

        {/* Share with another account */}
        <div style={cardStyle}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <Building2 size={16} style={{ color: "var(--sf-blue)" }} />
            <h2 style={{ fontSize: 14, fontWeight: 600, color: "var(--sf-text)", margin: 0 }}>Share with another account</h2>
          </div>
          <p style={{ fontSize: 12, color: "var(--sf-text-muted)", lineHeight: 1.5, margin: 0 }}>
            Creates a Snowflake share for the selected table and adds the target account.
          </p>
          <div>
            <label htmlFor="share-name" style={labelStyle}>Share name</label>
            <input id="share-name" value={shareName} onChange={(e) => setShareName(e.target.value)} placeholder="MY_DATA_SHARE" style={fieldStyle} />
          </div>
          <div>
            <label htmlFor="share-target" style={labelStyle}>Target account identifier</label>
            <input id="share-target" value={targetAccount} onChange={(e) => setTargetAccount(e.target.value)} placeholder="org-account" style={fieldStyle} />
          </div>
          <button type="button" onClick={submitShare} disabled={createDisabled} style={actionButtonStyle(createDisabled)}>
            {creating ? "Creating share..." : "Create Share"}
          </button>
          {createStatus && <StatusBanner status={createStatus} />}
        </div>
      </div>

      {/* Existing shares */}
      <div style={cardStyle}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <Share2 size={16} style={{ color: "var(--sf-blue)" }} />
            <h2 style={{ fontSize: 14, fontWeight: 600, color: "var(--sf-text)", margin: 0 }}>Existing shares</h2>
          </div>
          <span style={{ fontSize: 12, color: "var(--sf-text-muted)" }}>{existingShares.length} shares</span>
        </div>
        {loadingShares && <div style={{ padding: 16, textAlign: "center", fontSize: 13, color: "var(--sf-text-muted)" }}>Loading shares...</div>}
        {!loadingShares && sharesError && <StatusBanner status={{ kind: "error", text: sharesError }} />}
        {!loadingShares && !sharesError && existingShares.length === 0 && (
          <div style={{ padding: 16, textAlign: "center", fontSize: 13, color: "var(--sf-text-muted)" }}>No shares yet.</div>
        )}
        {!loadingShares && !sharesError && existingShares.length > 0 && (
          <div style={{ borderRadius: "var(--radius-md)", border: "1px solid var(--sf-border)", overflow: "auto" }}>
            <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
              <thead>
                <tr style={{ background: "var(--sf-dark)" }}>
                  <th style={thStyle}>Share</th>
                  <th style={thStyle}>Database</th>
                  <th style={thStyle}>Accounts</th>
                </tr>
              </thead>
              <tbody>
                {existingShares.map((share, i) => (
                  <tr key={i} style={{ borderBottom: "1px solid var(--sf-border)" }}>
                    <td style={{ ...tdStyle, fontFamily: "var(--font-fira-mono)" }}>{pickField(share, ["name", "NAME"])}</td>
                    <td style={tdStyle}>{pickField(share, ["database_name", "DATABASE_NAME"])}</td>
                    <td style={tdStyle}>{pickField(share, ["to", "TO"])}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
