'use client'

import { useReadContracts, useWatchContractEvent } from 'wagmi'
import { lotteryAbi } from '@/lib/generated'
import { useLotteryAddress } from './useLotteryAddress'

const REFETCH_INTERVAL_MS = 10_000

// Matches Lottery.sol's `enum Tier { ONE, FIVE, TEN }` ordering.
const TIERS = [0, 1, 2] as const

/** Reads the lottery's live pool, round, timing, and per-tier entry counts; refreshes on a timer and on relevant events. */
export function useLotteryData() {
  const address = useLotteryAddress()

  const { data, isLoading, error, refetch } = useReadContracts({
    contracts: address
      ? [
          { address, abi: lotteryAbi, functionName: 'getPoolBalanceETH' },
          { address, abi: lotteryAbi, functionName: 'getPoolBalanceUSD' },
          { address, abi: lotteryAbi, functionName: 'getRound' },
          { address, abi: lotteryAbi, functionName: 'getNextDrawTime' },
          { address, abi: lotteryAbi, functionName: 'getLotteryState' },
          { address, abi: lotteryAbi, functionName: 'getEntryCount', args: [TIERS[0]] },
          { address, abi: lotteryAbi, functionName: 'getEntryCount', args: [TIERS[1]] },
          { address, abi: lotteryAbi, functionName: 'getEntryCount', args: [TIERS[2]] },
        ]
      : [],
    query: {
      enabled: Boolean(address),
      refetchInterval: REFETCH_INTERVAL_MS,
    },
  })

  useWatchContractEvent({
    address,
    abi: lotteryAbi,
    eventName: 'TicketPurchased',
    onLogs: () => refetch(),
    enabled: Boolean(address),
  })

  useWatchContractEvent({
    address,
    abi: lotteryAbi,
    eventName: 'Winner',
    onLogs: () => refetch(),
    enabled: Boolean(address),
  })

  const [poolEth, poolUsd, round, nextDrawTime, lotteryState, entriesOne, entriesFive, entriesTen] =
    data ?? []

  return {
    address,
    isLoading,
    error,
    poolBalanceEth: poolEth?.result,
    poolBalanceUsd: poolUsd?.result,
    round: round?.result,
    nextDrawTime: nextDrawTime?.result,
    lotteryState: lotteryState?.result,
    entryCounts: [entriesOne?.result, entriesFive?.result, entriesTen?.result] as const,
    refetch,
  }
}
