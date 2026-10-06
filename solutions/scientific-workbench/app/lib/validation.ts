import crypto from "crypto"

// Snowflake identifiers are capped at 255 characters. The length bound is
// enforced here so an over-long name fails validation rather than being
// truncated by the server with a confusing error.
const IDENTIFIER_SEGMENT_RE = /^[A-Za-z_][A-Za-z0-9_$]{0,254}$/

/**
 * Validate and double-quote a single SQL identifier segment (no dots).
 * Throws if the segment contains invalid characters.
 */
export function quoteIdentifier(name: string): string {
  if (!IDENTIFIER_SEGMENT_RE.test(name)) {
    throw new Error(`Invalid SQL identifier: ${name.slice(0, 80)}`)
  }
  return `"${name}"`
}

/**
 * Validate and double-quote a qualified name like `DB.SCHEMA.TABLE`.
 * Each segment between dots is validated and quoted independently.
 */
export function quoteQualifiedName(name: string): string {
  const segments = name.split(".")
  if (segments.length === 0 || segments.length > 4) {
    throw new Error(`Invalid qualified name (expected 1-4 segments): ${name.slice(0, 120)}`)
  }
  return segments.map(quoteIdentifier).join(".")
}

/**
 * Validate that a column name is safe for DDL. Returns the sanitized,
 * uppercase name. Throws if the name is empty after sanitization.
 * A leading digit is prefixed with an underscore, since Snowflake
 * identifiers cannot start with a number.
 */
export function sanitizeColumnName(raw: string): string {
  const clean = raw
    .trim()
    .replace(/[^A-Z0-9_$]/gi, "_")
    .replace(/^([0-9])/, "_$1")
    .toUpperCase()
  if (!clean || !IDENTIFIER_SEGMENT_RE.test(clean)) {
    throw new Error(`Invalid column name: ${raw.slice(0, 80)}`)
  }
  return clean
}

/**
 * Generate a cryptographically random dollar-quote tag that cannot collide
 * with user input. Returns a string like `$_q7f2a1b8$`.
 */
export function generateDollarQuoteTag(): string {
  const hex = crypto.randomBytes(6).toString("hex")
  return `$_${hex}$`
}

/**
 * Return a generic JSON error response without leaking internal details.
 * The full error should be logged server-side before calling this.
 */
export function safeErrorResponse(genericMessage: string, status: number): Response {
  return Response.json({ error: genericMessage }, { status })
}

const MAX_UPLOAD_BYTES = 50 * 1024 * 1024 // 50 MB

export { MAX_UPLOAD_BYTES }
