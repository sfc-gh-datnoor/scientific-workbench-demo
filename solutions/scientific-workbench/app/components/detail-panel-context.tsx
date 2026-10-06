"use client"

import { createContext, useContext, useState, useCallback, type ReactNode } from "react"

interface DetailPanelState {
  title: string
  content: ReactNode
  open: boolean
}

interface DetailPanelContextValue {
  state: DetailPanelState
  setDetail: (title: string, content: ReactNode) => void
  clearDetail: () => void
}

const DetailPanelContext = createContext<DetailPanelContextValue | null>(null)

export function DetailPanelProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<DetailPanelState>({ title: "", content: null, open: false })

  const setDetail = useCallback((title: string, content: ReactNode) => {
    setState({ title, content, open: true })
  }, [])

  const clearDetail = useCallback(() => {
    setState({ title: "", content: null, open: false })
  }, [])

  return (
    <DetailPanelContext.Provider value={{ state, setDetail, clearDetail }}>
      {children}
    </DetailPanelContext.Provider>
  )
}

export function useDetailPanel() {
  const ctx = useContext(DetailPanelContext)
  if (!ctx) throw new Error("useDetailPanel must be used within DetailPanelProvider")
  return ctx
}
