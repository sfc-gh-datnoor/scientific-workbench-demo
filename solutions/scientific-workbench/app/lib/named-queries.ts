/**
 * Named Query Registry — server-side SQL allowlist for /api/query.
 *
 * SECURITY CONTRACT
 * -----------------
 * 1. No raw SQL from the client is ever executed. The client sends a query
 *    key (e.g. "schema_tables") and optional params; this registry maps it
 *    to a fixed SQL template.
 *
 * 2. Static queries (no params) have zero attack surface — the SQL is a
 *    compile-time constant.
 *
 * 3. Parameterized queries MUST declare a Zod schema for their params.
 *    The runner validates params before the handler runs. This is enforced
 *    by the TypeScript type: a ParameterizedNamedQuery without `paramsSchema`
 *    is a type error.
 *
 * 4. Params used in WHERE clauses MUST use bind variables (?), never string
 *    interpolation. Params used in FROM clauses (identifiers — can't be bound)
 *    MUST be validated with quoteIdentifier() AND checked against an explicit
 *    allowedSchemas / allowedDatabases set declared on the query entry.
 *
 * ADDING A NEW QUERY
 * ------------------
 * - Static: add an entry with `type: "static"` and a `sql` string.
 * - Parameterized: add an entry with `type: "parameterized"`, a `paramsSchema`
 *   (Zod object), and a `handler` function that returns { sql, binds? }.
 *   If the query interpolates identifiers, declare `allowedSchemas` and/or
 *   `allowedDatabases` on the entry (the handler must check them).
 */

import { z } from "zod"
import { quoteIdentifier } from "@/lib/validation"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface QueryResult {
  sql: string
  binds?: (string | number)[]
}

interface StaticNamedQuery {
  type: "static"
  description: string
  sql: string
}

interface ParameterizedNamedQuery {
  type: "parameterized"
  description: string
  paramsSchema: z.ZodTypeAny
  allowedSchemas?: ReadonlySet<string>
  allowedDatabases?: ReadonlySet<string>
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- params are Zod-validated by resolveNamedQuery before reaching the handler
  handler: (params: any) => QueryResult
}

export type NamedQuery = StaticNamedQuery | ParameterizedNamedQuery

// ---------------------------------------------------------------------------
// Shared allowlists
// ---------------------------------------------------------------------------

const WORKBENCH_SCHEMAS = new Set([
  "CATALOG", "WORKFLOWS", "GOVERNANCE", "PROVENANCE", "PROJECTS",
]) as ReadonlySet<string>

const REFERENCE_SCHEMAS = new Set([
  "GENOMICS", "CHEMBL", "CLINICAL", "PATHWAYS", "PROTEIN",
]) as ReadonlySet<string>

const ASSET_PREVIEW_SCHEMAS = new Set([
  ...WORKBENCH_SCHEMAS, ...REFERENCE_SCHEMAS,
]) as ReadonlySet<string>

const RESULT_SCHEMAS = new Set([
  ...WORKBENCH_SCHEMAS, "SHARED_ANALYTICS",
]) as ReadonlySet<string>

const ALLOWED_DATABASES = new Set([
  "SCIENTIFIC_WORKBENCH", "WORKBENCH_PROJECTS",
]) as ReadonlySet<string>

// ---------------------------------------------------------------------------
// Param schemas (Zod)
// ---------------------------------------------------------------------------

const IdentifierSchema = z.string().min(1).max(255).regex(
  /^[A-Za-z_][A-Za-z0-9_$]{0,254}$/,
  "Must be a valid SQL identifier"
)

const SchemaTableParams = z.object({
  schema: IdentifierSchema,
  table: IdentifierSchema,
})

const ResultPreviewParams = z.object({
  database: IdentifierSchema.optional(),
  schema: IdentifierSchema,
  table: IdentifierSchema,
})

const TablePreviewParams = z.object({
  schema: IdentifierSchema,
  table: IdentifierSchema,
  limit: z.coerce.number().int().min(1).max(200).optional(),
})

const AssetPreviewParams = z.object({
  schema_name: z.string().min(1).max(511),
  asset_name: IdentifierSchema,
  limit: z.coerce.number().int().min(1).max(100).optional(),
})

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

export const NAMED_QUERIES: Record<string, NamedQuery> = {
  schema_tables: {
    type: "static",
    description: "List all tables in SCIENTIFIC_WORKBENCH (excluding INFORMATION_SCHEMA)",
    sql: `SELECT TABLE_SCHEMA, TABLE_NAME FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA') ORDER BY TABLE_SCHEMA, TABLE_NAME`,
  },

  experiments_list: {
    type: "static",
    description: "Recent workflow runs with template names",
    sql: `SELECT r.RUN_ID, r.TEMPLATE_ID, t.DISPLAY_NAME AS TEMPLATE_NAME, r.STATUS, r.STARTED_AT, r.COMPLETED_AT, r.PARAMETERS, r.AGENT_SUMMARY, r.STEP_RESULTS FROM SCIENTIFIC_WORKBENCH.WORKFLOWS.RUNS r LEFT JOIN SCIENTIFIC_WORKBENCH.WORKFLOWS.TEMPLATES t ON r.TEMPLATE_ID = t.TEMPLATE_ID ORDER BY r.STARTED_AT DESC LIMIT 50`,
  },

  assets_list: {
    type: "static",
    description: "All assets in the catalog",
    sql: `SELECT ASSET_ID, ASSET_NAME, ASSET_TYPE, DOMAIN AS PROGRAM, OWNER, DESCRIPTION, SCHEMA_NAME, ROW_COUNT, NULL AS QUALITY_STATUS, CREATED_AT FROM SCIENTIFIC_WORKBENCH.CATALOG.ASSETS ORDER BY CREATED_AT DESC NULLS LAST LIMIT 200`,
  },

  promotion_log: {
    type: "static",
    description: "Governance promotion log",
    sql: `SELECT * FROM SCIENTIFIC_WORKBENCH.GOVERNANCE.PROMOTION_LOG ORDER BY ATTESTED_AT DESC NULLS LAST`,
  },

  canary_assertions: {
    type: "static",
    description: "Biological plausibility canary assertions",
    sql: `SELECT * FROM SCIENTIFIC_WORKBENCH.GOVERNANCE.CANARY_ASSERTIONS ORDER BY ASSERTION_ID`,
  },

  provenance_log: {
    type: "static",
    description: "Recent provenance log entries",
    sql: `SELECT * FROM SCIENTIFIC_WORKBENCH.PROVENANCE.PROVENANCE_LOG ORDER BY LOGGED_AT DESC LIMIT 50`,
  },

  column_info: {
    type: "parameterized",
    description: "Column metadata for a table (bind variables for schema/table)",
    paramsSchema: SchemaTableParams,
    handler: (p: z.infer<typeof SchemaTableParams>) => ({
      sql: `SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH FROM SCIENTIFIC_WORKBENCH.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION`,
      binds: [p.schema.toUpperCase(), p.table.toUpperCase()],
    }),
  },

  table_preview: {
    type: "parameterized",
    description: "Preview rows from a workbench table (schema allowlisted, identifier quoted)",
    paramsSchema: TablePreviewParams,
    allowedSchemas: WORKBENCH_SCHEMAS,
    handler: (p: z.infer<typeof TablePreviewParams>) => {
      const schema = p.schema.toUpperCase()
      const table = p.table.toUpperCase()
      if (!WORKBENCH_SCHEMAS.has(schema)) {
        throw new Error(`Schema ${schema} is not available for preview`)
      }
      const limit = Math.min(p.limit ?? 50, 200)
      const quoted = `"SCIENTIFIC_WORKBENCH".${quoteIdentifier(schema)}.${quoteIdentifier(table)}`
      return { sql: `SELECT * FROM ${quoted} LIMIT ${limit}` }
    },
  },

  experiment_results: {
    type: "parameterized",
    description: "Preview rows from an experiment output table (db + schema allowlisted)",
    paramsSchema: ResultPreviewParams,
    allowedSchemas: RESULT_SCHEMAS,
    allowedDatabases: ALLOWED_DATABASES,
    handler: (p: z.infer<typeof ResultPreviewParams>) => {
      const schema = p.schema.toUpperCase()
      const table = p.table.toUpperCase()
      const db = (p.database ?? "SCIENTIFIC_WORKBENCH").toUpperCase()
      if (!RESULT_SCHEMAS.has(schema)) {
        throw new Error(`Schema ${schema} is not available for result preview`)
      }
      if (!ALLOWED_DATABASES.has(db)) {
        throw new Error(`Database ${db} is not available for result preview`)
      }
      const quoted = `${quoteIdentifier(db)}.${quoteIdentifier(schema)}.${quoteIdentifier(table)}`
      return { sql: `SELECT * FROM ${quoted} LIMIT 100` }
    },
  },

  asset_column_info: {
    type: "parameterized",
    description: "Column metadata for an asset's underlying table (supports cross-database SCHEMA_NAME)",
    paramsSchema: AssetPreviewParams,
    allowedSchemas: ASSET_PREVIEW_SCHEMAS,
    allowedDatabases: ALLOWED_DATABASES,
    handler: (p: z.infer<typeof AssetPreviewParams>) => {
      const parts = p.schema_name.toUpperCase().split(".")
      let db: string, schema: string
      if (parts.length === 2) {
        db = parts[0]; schema = parts[1]
      } else {
        db = "SCIENTIFIC_WORKBENCH"; schema = parts[0]
      }
      if (!ALLOWED_DATABASES.has(db) && !ASSET_PREVIEW_SCHEMAS.has(schema)) {
        throw new Error(`Schema ${p.schema_name} is not available for column info`)
      }
      const table = p.asset_name.toUpperCase()
      return {
        sql: `SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH FROM ${quoteIdentifier(db)}.INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? ORDER BY ORDINAL_POSITION`,
        binds: [schema, table],
      }
    },
  },

  asset_preview: {
    type: "parameterized",
    description: "Preview rows from an asset's underlying table (supports cross-database SCHEMA_NAME)",
    paramsSchema: AssetPreviewParams,
    allowedSchemas: ASSET_PREVIEW_SCHEMAS,
    allowedDatabases: ALLOWED_DATABASES,
    handler: (p: z.infer<typeof AssetPreviewParams>) => {
      const parts = p.schema_name.toUpperCase().split(".")
      let db: string, schema: string
      if (parts.length === 2) {
        db = parts[0]; schema = parts[1]
      } else {
        db = "SCIENTIFIC_WORKBENCH"; schema = parts[0]
      }
      if (!ALLOWED_DATABASES.has(db) && !ASSET_PREVIEW_SCHEMAS.has(schema)) {
        throw new Error(`Schema ${p.schema_name} is not available for asset preview`)
      }
      const table = p.asset_name.toUpperCase()
      const limit = Math.min(p.limit ?? 20, 100)
      const quoted = `${quoteIdentifier(db)}.${quoteIdentifier(schema)}.${quoteIdentifier(table)}`
      return { sql: `SELECT * FROM ${quoted} LIMIT ${limit}` }
    },
  },
}

// ---------------------------------------------------------------------------
// Runner — validates params and resolves the SQL + binds
// ---------------------------------------------------------------------------

export function resolveNamedQuery(
  key: string,
  rawParams: Record<string, unknown> = {}
): QueryResult {
  const entry = NAMED_QUERIES[key]
  if (!entry) {
    throw new Error(
      `Unknown query: ${key}. Available: ${Object.keys(NAMED_QUERIES).join(", ")}`
    )
  }

  if (entry.type === "static") {
    return { sql: entry.sql }
  }

  const parsed = entry.paramsSchema.safeParse(rawParams)
  if (!parsed.success) {
    const issue = parsed.error.issues[0]
    throw new Error(`Invalid param "${issue?.path.join(".")}": ${issue?.message}`)
  }

  return entry.handler(parsed.data)
}
