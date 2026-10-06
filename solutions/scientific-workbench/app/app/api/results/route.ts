import { querySnowflake } from "@/lib/snowflake"
import { quoteQualifiedName, safeErrorResponse } from "@/lib/validation"
import { NextRequest } from "next/server"

export const dynamic = "force-dynamic"

// Only these qualified schema prefixes are accessible via this endpoint
const ALLOWED_SCHEMA_PREFIXES = [
  "SCIENTIFIC_WORKBENCH.CATALOG",
  "SCIENTIFIC_WORKBENCH.WORKFLOWS",
  "SCIENTIFIC_WORKBENCH.GOVERNANCE",
  "SCIENTIFIC_WORKBENCH.PROVENANCE",
  "SCIENTIFIC_WORKBENCH.PROJECTS",
  "WORKBENCH_PROJECTS.SHARED_ANALYTICS",
  "WORKBENCH_REFERENCE.",
]

function isAllowedTable(qualifiedName: string): boolean {
  const upper = qualifiedName.toUpperCase()
  return ALLOWED_SCHEMA_PREFIXES.some((prefix) => upper.startsWith(prefix))
}

export async function GET(req: NextRequest) {
  const table = req.nextUrl.searchParams.get("table")
  if (!table) {
    return safeErrorResponse("table parameter required", 400)
  }

  // Validate and quote the table name (each segment checked against identifier regex)
  let quotedTable: string
  try {
    quotedTable = quoteQualifiedName(table)
  } catch {
    return safeErrorResponse("Invalid table name format", 400)
  }

  // Authorization: only allow tables within workbench schemas
  if (!isAllowedTable(table)) {
    return safeErrorResponse("Access denied: table is outside the allowed workbench schemas", 403)
  }

  try {
    // Bind variable for the column metadata lookup
    const upperTable = table.toUpperCase()
    const columns = (await querySnowflake(
      `SELECT COLUMN_NAME, DATA_TYPE
       FROM INFORMATION_SCHEMA.COLUMNS
       WHERE TABLE_CATALOG || '.' || TABLE_SCHEMA || '.' || TABLE_NAME = ?
       ORDER BY ORDINAL_POSITION`,
      { binds: [upperTable] }
    )) as { COLUMN_NAME: string; DATA_TYPE: string }[]

    if (columns.length === 0) {
      // Try unqualified name under SCIENTIFIC_WORKBENCH
      const shortName = upperTable.split(".").pop() ?? upperTable
      const fallbackCols = (await querySnowflake(
        `SELECT COLUMN_NAME, DATA_TYPE
         FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_NAME = ?
         ORDER BY ORDINAL_POSITION`,
        { binds: [shortName] }
      )) as { COLUMN_NAME: string; DATA_TYPE: string }[]
      if (fallbackCols.length === 0) {
        return safeErrorResponse("Table not found", 404)
      }
      columns.push(...fallbackCols)
    }

    // Table name is validated + quoted (bind variables can't be used in FROM clause)
    const rows = await querySnowflake(`SELECT * FROM ${quotedTable} LIMIT 200`)

    return Response.json({ columns, rows, rowCount: rows.length })
  } catch (e) {
    console.error("[results API]", e)
    return safeErrorResponse("Failed to fetch results", 500)
  }
}
