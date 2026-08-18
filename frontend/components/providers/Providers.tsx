'use client'

import '@rainbow-me/rainbowkit/styles.css'

import { useEffect, useState, type ReactNode } from 'react'
import { WagmiProvider, type State } from 'wagmi'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { RainbowKitProvider, darkTheme } from '@rainbow-me/rainbowkit'
import { Toaster } from 'sonner'
import { config } from '@/lib/wagmi'

const rainbowKitTheme = darkTheme({
  accentColor: '#3b82f6',
  borderRadius: 'large',
})

export function Providers({
  children,
  initialState,
}: {
  children: ReactNode
  initialState?: State
}) {
  const [queryClient] = useState(() => new QueryClient())

  // Coinbase Wallet SDK injects its own telemetry script, which logs
  // "Analytics SDK: TypeError: Failed to fetch" whenever its endpoint is
  // unreachable (e.g. on localhost). Harmless, has no exposed toggle to
  // disable, and unrelated to our app's own errors — filter only that line.
  useEffect(() => {
    const originalError = console.error
    console.error = (...args: unknown[]) => {
      if (typeof args[0] === 'string' && args[0].includes('Analytics SDK')) return
      originalError(...args)
    }
    return () => {
      console.error = originalError
    }
  }, [])

  return (
    <WagmiProvider config={config} initialState={initialState}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={rainbowKitTheme}>
          {children}
          <Toaster theme="dark" richColors position="bottom-right" />
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  )
}
