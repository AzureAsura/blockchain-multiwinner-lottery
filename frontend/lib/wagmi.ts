import { createConfig, createStorage, cookieStorage, http } from 'wagmi'
import { anvil, baseSepolia } from 'wagmi/chains'
import { coinbaseWallet, injected } from 'wagmi/connectors'

export const config = createConfig({
  chains: [anvil, baseSepolia],
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
