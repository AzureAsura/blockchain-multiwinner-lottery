'use client'

import React from 'react'
import Link from 'next/link'
import { useChainId, useChains } from 'wagmi'
import { useCountdown } from '@/hooks/useCountdown'
import { useLotteryData } from '@/hooks/useLotteryData'
import { useWinnerHistory } from '@/hooks/useWinnerHistory'
import { formatCountdown, formatEth, truncateAddress } from '@/lib/format'
import { TIER_LABELS } from '@/lib/tiers'

export const WinnerSection = () => {
  const { nextDrawTime, lotteryState } = useLotteryData()
  const countdown = useCountdown(nextDrawTime, lotteryState)
  const { data: rounds, isLoading, error } = useWinnerHistory()

  const chainId = useChainId()
  const chains = useChains()
  const explorerUrl = chains.find((chain) => chain.id === chainId)?.blockExplorers?.default.url

  const countdownLabel =
    countdown.status === 'loading'
      ? '--:--:--:--'
      : countdown.status === 'calculating'
        ? 'Drawing…'
        : countdown.status === 'awaiting-draw'
          ? 'Awaiting draw…'
          : formatCountdown(countdown.secondsRemaining)

  const rows = (rounds ?? []).flatMap((round) =>
    round.winners.map((entry) => ({
      round: round.round,
      transactionHash: round.transactionHash,
      tier: entry.tier,
      winner: entry.winner,
      prize: entry.prize,
    })),
  )

  return (
    <div className="w-full">
      {/* Notch Timer Header (Fixed / Tidak Scroll) */}
      <div
        className="bg-[#030f1f]  pt-2.5 sm:pt-3 pb-3 sm:pb-4 px-2 sm:px-8 shadow-2xl relative z-10"
        style={{
          clipPath:
            'polygon(0% 45%, 15% 45%, 22% 0%, 78% 0%, 85% 45%, 100% 45%, 100% 100%, 0% 100%)',
          borderTopLeftRadius: '16px',
          borderTopRightRadius: '16px',
        }}
      >
        <div className="flex flex-col items-center justify-center">
          <div className="flex items-center gap-1 text-[10px] sm:text-xs text-slate-400 font-medium mb-0.5 sm:mb-1">
            <span className="w-3.5 h-3.5 sm:w-4 sm:h-4 rounded-full border border-slate-400 flex items-center justify-center text-[8px] sm:text-[10px]">
              ?
            </span>
            Time left
          </div>
          <div className="text-lg sm:text-3xl font-black tracking-widest text-white drop-shadow-[0_2px_10px_rgba(255,255,255,0.3)]">
            {countdownLabel}
          </div>
        </div>
      </div>

      {/* Main Container Table Box */}
      <div className="bg-[#030f1f]   rounded-b-2xl sm:rounded-b-3xl p-3 sm:p-6 shadow-2xl">
        {/* HANYA bagian ini yang dikasih overflow-x-auto untuk scroll samping */}
        <div className="w-full overflow-x-auto">
          <table className="w-full text-left border-collapse min-w-140 sm:min-w-160">
            <thead>
              <tr className="text-[10px] sm:text-[11px] text-slate-400 font-bold uppercase tracking-wider border-b border-slate-800/80">
                <th className="pb-3 sm:pb-4 pl-2 sm:pl-3">ROUND</th>
                <th className="pb-3 sm:pb-4">TIER</th>
                <th className="pb-3 sm:pb-4">WINNER</th>
                <th className="pb-3 sm:pb-4 text-right pr-2 sm:pr-3">PRIZE</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/50 text-xs sm:text-sm">
              {isLoading && (
                <tr>
                  <td colSpan={4} className="py-8 text-center text-slate-500">
                    Loading draw history…
                  </td>
                </tr>
              )}

              {!isLoading && error && (
                <tr>
                  <td colSpan={4} className="py-8 text-center text-slate-500">
                    Couldn&apos;t load draw history.
                  </td>
                </tr>
              )}

              {!isLoading && !error && rows.length === 0 && (
                <tr>
                  <td colSpan={4} className="py-8 text-center text-slate-500">
                    No draws yet.
                  </td>
                </tr>
              )}

              {!isLoading &&
                !error &&
                rows.map((row) => (
                  <tr key={`${row.transactionHash}-${row.tier}`} className="hover:bg-slate-800/20 transition-colors">
                    <td className="py-3 sm:py-4 pl-2 sm:pl-3 font-semibold text-slate-200">
                      {explorerUrl ? (
                        <Link
                          href={`${explorerUrl}/tx/${row.transactionHash}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="hover:text-white transition-colors"
                        >
                          #{row.round}
                        </Link>
                      ) : (
                        <span>#{row.round}</span>
                      )}
                    </td>
                    <td className="py-3 sm:py-4">
                      <span className="px-2 py-1 rounded-lg bg-[#4162FF]/20 text-[#4162FF] font-bold text-[10px] sm:text-xs">
                        {TIER_LABELS[row.tier]}
                      </span>
                    </td>
                    <td className="py-3 sm:py-4 font-mono text-slate-300 font-medium text-xs sm:text-sm">
                      {truncateAddress(row.winner)}
                    </td>
                    <td className="py-3 sm:py-4 text-right pr-2 sm:pr-3 font-bold text-slate-100">
                      {formatEth(row.prize)}
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
