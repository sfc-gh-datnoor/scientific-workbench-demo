import { GovernanceClient } from "./GovernanceClient"

export const dynamic = "force-dynamic"
export const metadata = { title: "Governance — Scientific Workbench" }

export default function GovernancePage() {
  return <GovernanceClient />
}
