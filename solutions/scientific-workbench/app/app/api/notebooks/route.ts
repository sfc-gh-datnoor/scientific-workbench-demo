import { querySnowflake } from "@/lib/snowflake"

const WORKSPACE = "SCIENTIFIC_WORKBENCH.CATALOG.SCIENTIFIC_WORKBENCH_NOTEBOOKS"

export async function GET() {
  try {
    const rows = await querySnowflake(
      `LIST 'snow://workspace/${WORKSPACE}/versions/last/'`
    )
    const notebooks = (rows as Record<string, unknown>[])
      .filter((r) => String(r.name ?? "").endsWith(".ipynb"))
      .map((r) => {
        const fullPath = String(r.name ?? "")
        const filename = fullPath.split("/").pop() ?? ""
        const name = filename.replace(/\.ipynb$/, "")
        return {
          name,
          filename,
          size: Number(r.size ?? 0),
          last_modified: String(r.last_modified ?? ""),
          workspace: WORKSPACE,
        }
      })
    return Response.json({ notebooks })
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Unknown error"
    return Response.json({ notebooks: [], error: msg })
  }
}
