import { NextRequest } from "next/server"
import { querySnowflake } from "@/lib/snowflake"

const IDENTIFIER_RE = /^[A-Za-z][A-Za-z0-9_]{0,254}$/
const ACCOUNT_RE = /^[A-Za-z][A-Za-z0-9_.$-]{0,254}$/

// Only these databases are browsable/shareable through the app
const ALLOWED_DATABASES = new Set([
  "SCIENTIFIC_WORKBENCH",
  "WORKBENCH_REFERENCE",
  "WORKBENCH_PROJECTS",
])

// Only workbench roles shown in the grant picker
const ALLOWED_ROLE_PREFIXES = ["WORKBENCH_"]

function validateId(value: string, label: string): string {
  if (!value || !IDENTIFIER_RE.test(value)) {
    throw new Error(`Invalid ${label}: ${value}`)
  }
  return value.toUpperCase()
}

function quoteId(value: string): string {
  return `"${validateId(value, "identifier").replace(/"/g, '""')}"`
}

function validateAllowedDb(db: string): string {
  const upper = validateId(db, "database")
  if (!ALLOWED_DATABASES.has(upper)) {
    throw new Error(`Access denied: database ${upper} is not part of the Scientific Workbench`)
  }
  return upper
}

export async function GET(request: NextRequest) {
  const params = request.nextUrl.searchParams
  const action = params.get("action") ?? ""

  try {
    switch (action) {
      case "databases": {
        const rows = [...ALLOWED_DATABASES].map((name) => ({ name }))
        return Response.json({ rows })
      }
      case "schemas": {
        const dbRaw = params.get("db") ?? ""
        validateAllowedDb(dbRaw)
        const db = quoteId(dbRaw)
        const rows = await querySnowflake(`SHOW SCHEMAS IN DATABASE ${db}`)
        const filtered = rows
          .map((r) => ({ name: r.name as string }))
          .filter((r) => !["INFORMATION_SCHEMA", "PUBLIC"].includes(r.name))
        return Response.json({ rows: filtered })
      }
      case "tables": {
        const dbRaw = params.get("db") ?? ""
        validateAllowedDb(dbRaw)
        const db = quoteId(dbRaw)
        const schema = quoteId(params.get("schema") ?? "")
        const rows = await querySnowflake(`SHOW TABLES IN SCHEMA ${db}.${schema}`)
        return Response.json({
          rows: rows.map((r) => ({ name: r.name, rows: r.rows ?? null, bytes: r.bytes ?? null })),
        })
      }
      case "roles": {
        const rows = await querySnowflake("SHOW ROLES")
        const filtered = rows
          .filter((r) => {
            const name = (r.name as string) ?? ""
            return ALLOWED_ROLE_PREFIXES.some((p) => name.startsWith(p))
          })
          .map((r) => ({ name: r.name, comment: r.comment ?? "" }))
        return Response.json({ rows: filtered })
      }
      case "user-roles": {
        const username = quoteId(params.get("username") ?? "")
        const rows = await querySnowflake(`SHOW GRANTS TO USER ${username}`)
        const filtered = rows
          .filter((r) => r.granted_on === "ROLE")
          .map((r) => ({ role: r.role ?? r.name ?? "" }))
          .filter((r) => ALLOWED_ROLE_PREFIXES.some((p) => (r.role as string).startsWith(p)))
        return Response.json({ rows: filtered })
      }
      case "grants": {
        const dbRaw = params.get("db") ?? ""
        validateAllowedDb(dbRaw)
        const db = quoteId(dbRaw)
        const schema = quoteId(params.get("schema") ?? "")
        const table = quoteId(params.get("table") ?? "")
        const rows = await querySnowflake(`SHOW GRANTS ON TABLE ${db}.${schema}.${table}`)
        return Response.json({ rows })
      }
      case "shares": {
        const rows = await querySnowflake("SHOW SHARES")
        return Response.json({
          rows: rows.map((r) => ({
            name: r.name ?? "",
            kind: r.kind ?? "",
            database_name: r.database_name ?? "",
            owner: r.owner ?? "",
            to: r.to ?? "",
            comment: r.comment ?? "",
          })),
        })
      }
      default:
        return Response.json({ error: "Unknown action" }, { status: 400 })
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Unknown error"
    return Response.json({ error: msg }, { status: 500 })
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const action = body.action ?? ""

    switch (action) {
      case "grant": {
        validateAllowedDb(body.database ?? "")
        const db = quoteId(body.database ?? "")
        const schema = quoteId(body.schema ?? "")
        const table = quoteId(body.table ?? "")
        const role = quoteId(body.role ?? "")
        const roleName = validateId(body.role ?? "", "role")
        if (!ALLOWED_ROLE_PREFIXES.some((p) => roleName.startsWith(p))) {
          return Response.json({ error: `Cannot grant to role ${roleName} — only workbench roles are allowed` }, { status: 403 })
        }
        await querySnowflake(`GRANT SELECT ON TABLE ${db}.${schema}.${table} TO ROLE ${role}`)
        return Response.json({ message: `Granted SELECT on ${body.database}.${body.schema}.${body.table} to role ${body.role}` })
      }
      case "create": {
        validateAllowedDb(body.database ?? "")
        const share = quoteId(body.share_name ?? "")
        const db = quoteId(body.database ?? "")
        const schema = quoteId(body.table_schema ?? "")
        const table = quoteId(body.table_name ?? "")
        const account = body.target_account ?? ""
        if (!ACCOUNT_RE.test(account)) {
          return Response.json({ error: `Invalid account identifier: ${account}` }, { status: 400 })
        }
        const steps: { step: string; result: Record<string, unknown>[] }[] = []

        let r = await querySnowflake(`CREATE SHARE IF NOT EXISTS ${share}`)
        steps.push({ step: "CREATE SHARE", result: r })

        r = await querySnowflake(`GRANT USAGE ON DATABASE ${db} TO SHARE ${share}`)
        steps.push({ step: "GRANT USAGE ON DATABASE", result: r })

        r = await querySnowflake(`GRANT USAGE ON SCHEMA ${db}.${schema} TO SHARE ${share}`)
        steps.push({ step: "GRANT USAGE ON SCHEMA", result: r })

        r = await querySnowflake(`GRANT SELECT ON TABLE ${db}.${schema}.${table} TO SHARE ${share}`)
        steps.push({ step: "GRANT SELECT ON TABLE", result: r })

        r = await querySnowflake(`ALTER SHARE ${share} ADD ACCOUNTS = ${account}`)
        steps.push({ step: "ADD ACCOUNTS", result: r })

        return Response.json({
          message: `Share ${body.share_name} created and shared to ${account}`,
          steps,
        })
      }
      default:
        return Response.json({ error: "Unknown action" }, { status: 400 })
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Unknown error"
    return Response.json({ error: msg }, { status: 500 })
  }
}
