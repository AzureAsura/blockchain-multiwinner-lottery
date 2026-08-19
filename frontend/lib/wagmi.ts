import { createConfig, createStorage, cookieStorage, http } from 'wagmi'
import { anvil, baseSepolia } from 'wagmi/chains'
import { coinbaseWallet, injected } from 'wagmi/connectors'

export const config = createConfig({
  // baseSepolia listed first: wagmi uses chains[0] as the default chain before
  // a wallet connects, so reads (pool, round, ...) work for a fresh visitor
  // without requiring them to connect + switch network first.
  chains: [baseSepolia, anvil],
  connectors: [injected(), coinbaseWallet({ appName: 'Nirmala Lottery' })],
  transports: {
    [anvil.id]: http(process.env.NEXT_PUBLIC_ANVIL_RPC_URL),
    [baseSepolia.id]: http(process.env.NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL),
  },
  ssr: true,
  storage: createStorage({ storage: cookieStorage }),
})

declare module 'wagmi' {
  interface Register {
    config: typeof config
  }
}
