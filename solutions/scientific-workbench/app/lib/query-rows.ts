/**
 * Normalise a /api/query JSON response into a row array.
 *
 * WHY THIS EXISTS
 * /api/query answers a failed query with a JSON error object plus a non-2xx
 * status. `res.json()` resolves happily for that body, so the old idiom
 *
 *     const rows = (data.rows || data || []) as Row[]
 *
 * assigned the error OBJECT into state whenever a query failed. The next
 * `rows.map(...)` then threw a TypeError and React unmounted the route, which
 * the browser rendered as a blank "This page couldn't load" screen. A wrong
 * column name in one query took down an entire page instead of showing an
 * empty table.
 *
 * Always route query responses through this helper. It returns an array or an
 * empty array, never anything else.
 */
export function toRows<T>(data: unknown): T[] {
  if (Array.isArray(data)) return data as T[]
  if (data && typeof data === "object") {
    const rows = (data as { rows?: unknown }).rows
    if (Array.isArray(rows)) return rows as T[]
  }
  return []
}

/**
 * Pull a human-readable error out of a /api/query response, if it carried one.
 * Returns null when the response looks like a normal result set.
 */
export function queryError(data: unknown): string | null {
  if (!data || typeof data !== "object" || Array.isArray(data)) return null
  const err = (data as { error?: unknown }).error
  if (typeof err === "string" && err.trim()) return err
  return null
}
