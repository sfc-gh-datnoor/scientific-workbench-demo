import { NextRequest, NextResponse } from "next/server"
import { querySnowflake } from "@/lib/snowflake"
import { quoteIdentifier } from "@/lib/validation"

/**
 * GET /api/asset-preview?id=<asset_id>
 *
 * Looks up an asset by ID in CATALOG.ASSETS, resolves its underlying table,
 * and returns column schema + sample rows. The catalog IS the allowlist:
 * if the asset_id doesn't exist in CATALOG.ASSETS, the request is denied.
 * No hardcoded database allowlists needed.
 */
export async function GET(request: NextRequest) {
  const assetId = request.nextUrl.searchParams.get("id")
  if (!assetId) {
    return NextResponse.json({ error: "Missing ?id= parameter" }, { status: 400 })
  }

  // Step 1: Look up asset in catalog (bind variable — safe)
  const assets = await querySnowflake(
    `SELECT ASSET_ID, ASSET_NAME, ASSET_TYPE, SCHEMA_NAME
     FROM SCIENTIFIC_WORKBENCH.CATALOG.ASSETS
     WHERE ASSET_ID = ?`,
    { binds: [assetId] }
  )

  if (assets.length === 0) {
    return NextResponse.json({ error: "Asset not found" }, { status: 404 })
  }

  const asset = assets[0]
  const schemaName: string = asset.SCHEMA_NAME || ""

  if (!schemaName) {
    return NextResponse.json({ error: "Asset has no schema_name" }, { status: 400 })
  }

  // Step 2: Resolve DB, SCHEMA, TABLE from the asset record
  const resolved = resolveTable(assetId, schemaName)

  try {
    if (resolved.table) {
      // Known table — fetch columns + preview in parallel
      const qualifiedInfo = `${quoteIdentifier(resolved.db)}.INFORMATION_SCHEMA.COLUMNS`
      const qualifiedTable = `${quoteIdentifier(resolved.db)}.${quoteIdentifier(resolved.schema)}.${quoteIdentifier(resolved.table)}`

      const [columns, rows] = await Promise.all([
        querySnowflake(
          `SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH
           FROM ${qualifiedInfo}
           WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
           ORDER BY ORDINAL_POSITION`,
          { binds: [resolved.schema, resolved.table] }
        ),
        querySnowflake(`SELECT * FROM ${qualifiedTable} LIMIT 20`),
      ])

      return NextResponse.json({ columns, rows, table: `${resolved.db}.${resolved.schema}.${resolved.table}` })
    } else {
      // Table unknown — list tables in the schema + show columns for all
      const qualifiedInfo = `${quoteIdentifier(resolved.db)}.INFORMATION_SCHEMA`

      const [tables, columns] = await Promise.all([
        querySnowflake(
          `SELECT TABLE_NAME, TABLE_TYPE, ROW_COUNT, COMMENT
           FROM ${qualifiedInfo}.TABLES
           WHERE TABLE_SCHEMA = ? AND TABLE_TYPE IN ('BASE TABLE', 'VIEW')
           ORDER BY TABLE_NAME`,
          { binds: [resolved.schema] }
        ),
        querySnowflake(
          `SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE
           FROM ${qualifiedInfo}.COLUMNS
           WHERE TABLE_SCHEMA = ?
           ORDER BY TABLE_NAME, ORDINAL_POSITION`,
          { binds: [resolved.schema] }
        ),
      ])

      // If schema has exactly one table, preview it
      let rows: Record<string, unknown>[] = []
      let previewTable: string | null = null
      if (tables.length === 1) {
        previewTable = `${resolved.db}.${resolved.schema}.${tables[0].TABLE_NAME}`
        const qt = `${quoteIdentifier(resolved.db)}.${quoteIdentifier(resolved.schema)}.${quoteIdentifier(tables[0].TABLE_NAME as string)}`
        rows = await querySnowflake(`SELECT * FROM ${qt} LIMIT 20`)
      }

      return NextResponse.json({ tables, columns, rows, table: previewTable, schema: `${resolved.db}.${resolved.schema}` })
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Query failed"
    return NextResponse.json({ error: msg }, { status: 500 })
  }
}

function resolveTable(assetId: string, schemaName: string): { db: string; schema: string; table: string | null } {
  // Format: asset-data-DB.SCHEMA.TABLE (from SEED_ASSETS)
  const match = assetId.match(/^asset-data-([^.]+)\.([^.]+)\.(.+)$/)
  if (match) {
    return { db: match[1], schema: match[2], table: match[3] }
  }
  // Other formats (DS-001, veracyte-*): derive db+schema from schema_name
  const parts = schemaName.toUpperCase().split(".")
  if (parts.length === 2) {
    return { db: parts[0], schema: parts[1], table: null }
  }
  return { db: "SCIENTIFIC_WORKBENCH", schema: parts[0], table: null }
}
