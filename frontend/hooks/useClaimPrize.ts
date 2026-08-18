'use client'

import { useAccount, useChains, useReadContract, useSimulateContract, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import { lotteryAbi } from '@/lib/generated'
import { useLotteryAddress } from './useLotteryAddress'

export type ClaimPrizeDisabledReason =
  | 'not-connected'
  | 'unsupported-chain'
  | 'not-deployed'
  | 'nothing-to-claim'
  | 'simulation-failed'
  | null

/** Reads the caller's claimable prize balance (the push-payout fallback) and prepares/sends a claimPrize() transaction. */
export function useClaimPrize() {
  const { address: account, isConnected, chainId } = useAccount()
  const chains = useChains()
  const address = useLotteryAddress()

  const isChainSupported = chains.some((chain) => chain.id === chainId)

  const claimable = useReadContract({
    address,
    abi: lotteryAbi,
    functionName: 'getClaimablePrize',
    args: account ? [account] : undefined,
    query: {
      enabled: Boolean(address && account),
      refetchInterval: 10_000,
    },
  })

  const claimableAmount = claimable.data
  const hasClaimable = claimableAmount !== undefined && claimableAmount > 0n

  const canSimulate = isConnected && isChainSupported && Boolean(address) && hasClaimable

  const simulation = useSimulateContract({
    address,
    abi: lotteryAbi,
    functionName: 'claimPrize',
    query: { enabled: canSimulate },
  })

  const write = useWriteContract()
  const receipt = useWaitForTransactionReceipt({ hash: write.data })

  const disabledReason: ClaimPrizeDisabledReason = !isConnected
    ? 'not-connected'
    : !isChainSupported
      ? 'unsupported-chain'
      : !address
        ? 'not-deployed'
        : !hasClaimable
          ? 'nothing-to-claim'
          : simulation.error
            ? 'simulation-failed'
            : null

  function claim() {
    if (!simulation.data) return
    write.writeContract(simulation.data.request)
  }

  return {
    claim,
    claimableAmount,
    disabledReason,
    canClaim: disabledReason === null && Boolean(simulation.data),
    isSimulating: simulation.isLoading,
    simulationError: simulation.error,
    isPending: write.isPending,
    isConfirming: receipt.isLoading,
    isSuccess: receipt.isSuccess,
    writeError: write.error,
    reset: write.reset,
  }
}
