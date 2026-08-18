'use client'

import { useBuyTicket, type BuyTicketDisabledReason } from '@/hooks/useBuyTicket'
import { describeContractError } from '@/lib/errors'
import { TIER_LABELS, type Tier } from '@/lib/tiers'
import { TxStatusToast } from './TxStatusToast'

const DISABLED_LABELS: Record<Exclude<BuyTicketDisabledReason, null>, string> = {
  'not-connected': 'Connect your wallet to buy a ticket',
  'unsupported-chain': 'Switch to a supported network',
  'not-deployed': 'Lottery is not deployed on this network yet',
  calculating: 'A draw is in progress — purchases are paused',
  'simulation-failed': 'Unable to buy right now',
}

/** Buys a ticket for the given tier — the selected tier is owned by a parent (see TierSelector). */
export function BuyTicketButton({ tier }: { tier: Tier }) {
  const buyTicket = useBuyTicket(tier)

  const errorMessage = buyTicket.writeError ? describeContractError(buyTicket.writeError) : null

  const isBusy = buyTicket.isPending || buyTicket.isConfirming
  const buttonLabel = buyTicket.isPending
    ? 'Confirm in wallet…'
    : buyTicket.isConfirming
      ? 'Confirming…'
      : `Buy ticket ${TIER_LABELS[tier]}`

  return (
    <div className="flex flex-col items-center gap-3 w-full">
      <button
        type="button"
        onClick={buyTicket.buy}
        disabled={!buyTicket.canBuy || isBusy}
        className="mt-4 sm:mt-5 btn-color font-black text-xs sm:text-base tracking-widest uppercase px-8 sm:px-12 py-3 sm:py-3.5 rounded-2xl transition-all disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {buttonLabel}
      </button>

      {buyTicket.disabledReason && !isBusy && (
        <p className="text-xs text-white/60">{DISABLED_LABELS[buyTicket.disabledReason]}</p>
      )}

      <TxStatusToast
        isPending={buyTicket.isPending}
        isConfirming={buyTicket.isConfirming}
        isSuccess={buyTicket.isSuccess}
        error={errorMessage}
        pendingMessage="Confirm the purchase in your wallet…"
        confirmingMessage="Waiting for confirmation…"
        successMessage="Ticket purchased!"
      />
    </div>
  )
}
