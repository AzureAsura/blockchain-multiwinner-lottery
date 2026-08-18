'use client'

import { useChainId } from 'wagmi'
import { getLotteryAddress } from '@/lib/contracts'

/** Returns the Lottery contract address for the currently connected chain, or undefined if not deployed there. */
export function useLotteryAddress() {
  const chainId = useChainId()
  return getLotteryAddress(chainId)
}
