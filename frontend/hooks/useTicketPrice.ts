'use client'

import { useReadContract } from 'wagmi'
import { lotteryAbi } from '@/lib/generated'
import type { Tier } from '@/lib/tiers'
import { useLotteryAddress } from './useLotteryAddress'

/** Reads the current ETH price (in wei) for a ticket tier. Reverts with Lottery__StalePrice if the price feed is stale. */
export function useTicketPrice(tier: Tier) {
  const address = useLotteryAddress()

  return useReadContract({
    address,
    abi: lotteryAbi,
    functionName: 'getTicketPriceInWei',
    args: [tier],
    query: {
      enabled: Boolean(address),
      refetchInterval: 10_000,
    },
  })
}
