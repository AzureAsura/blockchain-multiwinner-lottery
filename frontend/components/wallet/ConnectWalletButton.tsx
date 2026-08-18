'use client'

import { ConnectButton } from '@rainbow-me/rainbowkit'
import { truncateAddress } from '@/lib/format'

export function ConnectWalletButton() {
  return (
    <ConnectButton.Custom>
      {({ account, chain, openAccountModal, openChainModal, openConnectModal, mounted }) => {
        const ready = mounted
        const connected = ready && account && chain

        return (
          <div
            aria-hidden={!ready}
            style={!ready ? { opacity: 0, pointerEvents: 'none', userSelect: 'none' } : undefined}
          >
            {!connected && (
              <button
                onClick={openConnectModal}
                className="flex items-center gap-2.5 btn-color hover:brightness-110 px-4 py-2 rounded-xl shadow-lg shadow-blue-500/20 border border-blue-400/20 cursor-pointer transition-all active:scale-95"
              >
                <span className="text-xs md:text-sm font-bold text-white tracking-wide">
                  Connect Wallet
                </span>
              </button>
            )}

            {connected && chain.unsupported && (
              <button
                onClick={openChainModal}
                className="flex items-center gap-2.5 bg-red-500/80 hover:bg-red-500 px-4 py-2 rounded-xl shadow-lg shadow-red-500/20 border border-red-400/20 cursor-pointer transition-all active:scale-95"
              >
                <span className="text-xs md:text-sm font-bold text-white tracking-wide">
                  Wrong network
                </span>
              </button>
            )}

            {connected && !chain.unsupported && (
              <button
                onClick={openAccountModal}
                className="flex items-center gap-2.5 btn-color hover:brightness-110 px-4 py-2 rounded-xl shadow-lg shadow-blue-500/20 border border-blue-400/20 cursor-pointer transition-all active:scale-95"
              >
                <div className="w-6 h-6 rounded-lg bg-white/20 flex items-center justify-center text-xs text-white">
                  👻
                </div>
                <span className="text-xs md:text-sm font-bold text-white tracking-wide">
                  {truncateAddress(account.address)}
                </span>
              </button>
            )}
          </div>
        )
      }}
    </ConnectButton.Custom>
  )
}
