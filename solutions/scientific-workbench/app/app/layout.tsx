import type { Metadata } from "next"
import { Inter, Fira_Mono } from "next/font/google"
import "./globals.css"
import { QueryProvider } from "@/components/query-provider"
import { ThemeProvider } from "@/components/theme-provider"
import { AppShell } from "@/components/app-shell-layout"

const inter = Inter({ subsets: ["latin"], variable: "--font-inter", display: "swap" })
const firaMono = Fira_Mono({
  subsets: ["latin"],
  weight: ["400", "500", "700"],
  variable: "--font-fira-mono",
  display: "swap",
})

export const metadata: Metadata = {
  title: "Scientific Workbench",
  description: "AI-powered life sciences R&D platform",
  icons: {
    icon: [{ url: "/snowflake-logo.svg", type: "image/svg+xml" }],
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className={`${inter.variable} ${firaMono.variable}`} suppressHydrationWarning>
      <body>
        <ThemeProvider>
          <QueryProvider>
            <AppShell>{children}</AppShell>
          </QueryProvider>
        </ThemeProvider>
      </body>
    </html>
  )
}
