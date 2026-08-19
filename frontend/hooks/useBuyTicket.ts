'use client'

import { useAccount, useChains, useSimulateContract, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { lotteryAbi } from '@/lib/generated'
import type { Tier } from '@/lib/tiers'
import { useCountdown } from './useCountdown'
import { useLotteryAddress } from './useLotteryAddress'
import { useLotteryData } from './useLotteryData'
import { useTicketPrice } from './useTicketPrice'

// Matches Lottery.sol's `enum LotteryState { OPEN, CALCULATING }` ordering.
const LOTTERY_STATE_CALCULATING = 1

// buyTicket re-prices on-chain and refunds any overpayment, so a small buffer
// over the quoted price absorbs price movement between quote and confirmation
// without risking Lottery__InsufficientPayment.
const BUFFER_NUMERATOR = 102n
const BUFFER_DENOMINATOR = 100n

export type BuyTicketDisabledReason =
  | 'not-connected'
  | 'unsupported-chain'
  | 'not-deployed'
  | 'calculating'
  | 'awaiting-draw'
  | 'simulation-failed'
  | null

/** Prepares and sends a buyTicket(tier) transaction, gated by a simulate-before-write check. */
export function useBuyTicket(tier: Tier) {
  const { isConnected, chainId } = useAccount()
  const chains = useChains()
  const address = useLotteryAddress()
  const { lotteryState, nextDrawTime } = useLotteryData()
  const { data: price } = useTicketPrice(tier)
  const countdown = useCountdown(nextDrawTime, lotteryState)

  const value = price !== undefined ? (price * BUFFER_NUMERATOR) / BUFFER_DENOMINATOR : undefined

  const isChainSupported = chains.some((chain) => chain.id === chainId)
  const isCalculating = lotteryState === LOTTERY_STATE_CALCULATING
  // The contract itself still accepts purchases once the interval elapses (state only
  // flips to CALCULATING once performUpkeep actually runs) — this is a UX guard only,
  // so a ticket bought right as a draw is due doesn't feel like it vanished into limbo.
  const isAwaitingDraw = countdown.status === 'awaiting-draw'

  const canSimulate =
    isConnected && isChainSupported && Boolean(address) && value !== undefined && !isCalculating && !isAwaitingDraw

  const simulation = useSimulateContract({
    address,
    abi: lotteryAbi,
    functionName: 'buyTicket',
    args: [tier],
    value,
    query: {
      enabled: canSimulate,
    },
  })

  const write = useWriteContract()
  const receipt = useWaitForTransactionReceipt({ hash: write.data })

  const disabledReason: BuyTicketDisabledReason = !isConnected
    ? 'not-connected'
    : !isChainSupported
      ? 'unsupported-chain'
      : !address
        ? 'not-deployed'
        : isCalculating
          ? 'calculating'
          : isAwaitingDraw
            ? 'awaiting-draw'
            : simulation.error
              ? 'simulation-failed'
              : null

  function buy() {
    if (!simulation.data) return
    write.writeContract(simulation.data.request)
  }

  return {
    buy,
    price,
    value,
    disabledReason,
    canBuy: disabledReason === null && Boolean(simulation.data),
    isSimulating: simulation.isLoading,
    simulationError: simulation.error,
    isPending: write.isPending,
    isConfirming: receipt.isLoading,
    isSuccess: receipt.isSuccess,
    writeError: write.error,
    reset: write.reset,
  }
}
