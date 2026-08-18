'use client'

import { useClaimPrize } from '@/hooks/useClaimPrize'
import { describeContractError } from '@/lib/errors'
import { formatEth } from '@/lib/format'
import { TxStatusToast } from './TxStatusToast'

/** Shown only when the connected wallet has a claimable prize balance (a push payout that previously failed). */
export function ClaimPrizeBanner() {
  const claimPrize = useClaimPrize()

  const errorMessage = claimPrize.writeError ? describeContractError(claimPrize.writeError) : null
  const isBusy = claimPrize.isPending || claimPrize.isConfirming

  if (!claimPrize.claimableAmount || claimPrize.claimableAmount === 0n) {
    return null
  }

  return (
    <div className="card flex flex-col sm:flex-row items-center justify-between gap-3 rounded-xl sm:rounded-2xl px-4 sm:px-6 py-3 sm:py-4 border border-blue-400/20 w-full max-w-md">
      <div className="text-center sm:text-left">
        <p className="text-xs sm:text-sm font-bold text-white">You have a prize to claim</p>
        <p className="text-[11px] sm:text-xs text-white/60">{formatEth(claimPrize.claimableAmount)}</p>
      </div>

      <button
        type="button"
        onClick={claimPrize.claim}
        disabled={!claimPrize.canClaim || isBusy}
        className="btn-color font-bold text-xs sm:text-sm px-5 py-2 rounded-xl transition-all disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {claimPrize.isPending ? 'Confirm in wallet…' : claimPrize.isConfirming ? 'Confirming…' : 'Claim'}
      </button>

      <TxStatusToast
        isPending={claimPrize.isPending}
        isConfirming={claimPrize.isConfirming}
        isSuccess={claimPrize.isSuccess}
        error={errorMessage}
        pendingMessage="Confirm the claim in your wallet…"
        confirmingMessage="Waiting for confirmation…"
        successMessage="Prize claimed!"
      />
    </div>
  )
}
