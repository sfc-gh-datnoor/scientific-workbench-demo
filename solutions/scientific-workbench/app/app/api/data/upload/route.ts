import { querySnowflakeLongRunning } from "@/lib/snowflake"
import { sanitizeColumnName, quoteIdentifier, safeErrorResponse, MAX_UPLOAD_BYTES } from "@/lib/validation"
import { NextRequest } from "next/server"

export const dynamic = "force-dynamic"

const SCHEMA_PATH = "WORKBENCH_PROJECTS.SHARED_ANALYTICS"

export async function POST(req: NextRequest) {
  try {
    const formData = await req.formData()
    const file = formData.get("file") as File | null
    const datasetName = formData.get("dataset_name") as string
    const description = formData.get("description") as string
    const domain = formData.get("domain") as string

    if (!file || !datasetName) {
      return safeErrorResponse("file and dataset_name required", 400)
    }

    // Server-side file size limit
    if (file.size > MAX_UPLOAD_BYTES) {
      return safeErrorResponse(`File exceeds ${MAX_UPLOAD_BYTES / 1024 / 1024}MB limit`, 413)
    }

    // Sanitize and validate table name
    const tableName = datasetName.replace(/[^A-Z0-9_]/gi, "_").toUpperCase()
    let quotedTable: string
    try {
      quotedTable = `${quoteIdentifier(SCHEMA_PATH.split(".")[0])}.${quoteIdentifier(SCHEMA_PATH.split(".")[1])}.${quoteIdentifier(tableName)}`
    } catch {
      return safeErrorResponse("Invalid dataset name", 400)
    }

    // Step 1: Ensure stage exists (no user input)
    await querySnowflakeLongRunning(
      `CREATE STAGE IF NOT EXISTS ${quoteIdentifier(SCHEMA_PATH.split(".")[0])}.${quoteIdentifier(SCHEMA_PATH.split(".")[1])}."DATA_STAGE"
       FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"')`
    )

    // Step 2: Parse CSV headers and validate column names
    const text = await file.text()
    const lines = text.split("\n")
    if (lines.length === 0) {
      return safeErrorResponse("File is empty", 400)
    }

    let headers: string[]
    try {
      headers = lines[0].split(",").map((h) => sanitizeColumnName(h))
    } catch (e) {
      return safeErrorResponse("Invalid column names in CSV header", 400)
    }

    if (headers.length === 0) {
      return safeErrorResponse("No columns found in CSV header", 400)
    }

    // Step 3: Create table with quoted, validated column names
    const columnDefs = headers.map((h) => `${quoteIdentifier(h)} VARCHAR`).join(", ")
    const commentBind = description || datasetName
    await querySnowflakeLongRunning(
      `CREATE OR REPLACE TABLE ${quotedTable} (${columnDefs}) COMMENT = ?`,
      { binds: [commentBind] }
    )

    // Step 4: Batch INSERT with bind variables
    const dataRows = lines.slice(1).filter((l) => l.trim())
    if (dataRows.length > 0 && dataRows.length <= 10000) {
      const batchSize = 500
      const placeholderRow = `(${headers.map(() => "?").join(",")})`

      for (let i = 0; i < dataRows.length; i += batchSize) {
        const batch = dataRows.slice(i, i + batchSize)
        const binds: (string | null)[] = []
        const valueClauses: string[] = []

        for (const row of batch) {
          const cells = row.split(",").map((c) => c.trim())
          // Pad or truncate cells to match header count
          for (let j = 0; j < headers.length; j++) {
            binds.push(cells[j] ?? null)
          }
          valueClauses.push(placeholderRow)
        }

        await querySnowflakeLongRunning(
          `INSERT INTO ${quotedTable} VALUES ${valueClauses.join(",\n")}`,
          { binds }
        )
      }
    }

    // Step 5: Register in asset catalog with bind variables
    await querySnowflakeLongRunning(
      `INSERT INTO SCIENTIFIC_WORKBENCH.CATALOG.ASSETS
       (asset_id, asset_name, asset_type, description, domain, schema_name, owner, row_count, created_at)
       VALUES (UUID_STRING(), ?, 'dataset', ?, ?, ?, CURRENT_USER(), ?, CURRENT_TIMESTAMP())`,
      { binds: [tableName, description || `Uploaded dataset: ${datasetName}`, domain || "uploaded", SCHEMA_PATH, dataRows.length] }
    )

    return Response.json({
      message: `Dataset ${tableName} created with ${dataRows.length} rows and registered in catalog`,
      table: `${SCHEMA_PATH}.${tableName}`,
      rows: dataRows.length,
      columns: headers,
    })
  } catch (e) {
    console.error(new Date().toISOString(), "[data upload error]", e)
    return safeErrorResponse("Upload failed", 500)
  }
}
