'use client'

import { useQuery } from '@tanstack/react-query'
import { getAbiItem, type Address, type Log, type PublicClient } from 'viem'
import { useChainId, usePublicClient } from 'wagmi'
import { getLotteryDeployBlock } from '@/lib/contracts'
import { lotteryAbi } from '@/lib/generated'
import type { Tier } from '@/lib/tiers'
import { useLotteryAddress } from './useLotteryAddress'
import { useLotteryData } from './useLotteryData'

const winnerEvent = getAbiItem({ abi: lotteryAbi, name: 'Winner' })

// Public RPCs commonly cap eth_getLogs to ~10k blocks per call; stay under that.
const BLOCK_RANGE_CHUNK = 9_000n
// Stop scanning further back once this many completed rounds are collected.
const TARGET_ROUND_COUNT = 20

export type WinnerEntry = { tier: Tier; winner: Address; prize: bigint }
export type WinnerRound = {
  round: number
  transactionHash: `0x${string}`
  blockNumber: bigint
  winners: WinnerEntry[]
}

type WinnerLog = Log<bigint, number, false, typeof winnerEvent, undefined, [typeof winnerEvent]>

async function fetchWinnerRounds({
  publicClient,
  address,
  deployBlock,
  currentRound,
}: {
  publicClient: PublicClient
  address: Address
  deployBlock: bigint
  currentRound: bigint
}): Promise<WinnerRound[]> {
  const latestBlock = await publicClient.getBlockNumber()

  const collectedLogs: WinnerLog[] = []
  const seenTxHashes = new Set<string>()
  let toBlock = latestBlock

  while (toBlock >= deployBlock) {
    const fromBlockCandidate = toBlock - BLOCK_RANGE_CHUNK + 1n
    const fromBlock = fromBlockCandidate > deployBlock ? fromBlockCandidate : deployBlock

    const logs = (await publicClient.getLogs({
      address,
      event: winnerEvent,
      fromBlock,
      toBlock,
    })) as WinnerLog[]

    collectedLogs.push(...logs)
    for (const log of logs) seenTxHashes.add(log.transactionHash)

    if (fromBlock === deployBlock || seenTxHashes.size >= TARGET_ROUND_COUNT) break
    toBlock = fromBlock - 1n
  }

  const roundsByTxHash = new Map<string, WinnerRound>()
  for (const log of collectedLogs) {
    const entry: WinnerEntry = {
      tier: log.args.tier as Tier,
      winner: log.args.winner as Address,
      prize: log.args.prize as bigint,
    }

    const existing = roundsByTxHash.get(log.transactionHash)
    if (existing) {
      existing.winners.push(entry)
    } else {
      roundsByTxHash.set(log.transactionHash, {
        round: 0,
        transactionHash: log.transactionHash,
        blockNumber: log.blockNumber,
        winners: [entry],
      })
    }
  }

  const rounds = [...roundsByTxHash.values()].sort((a, b) => (a.blockNumber < b.blockNumber ? 1 : -1))

  // Every completed draw increments s_round exactly once (fulfillRandomWords only,
  // never the DrawSkipped path), so counting back from the current round is exact.
  rounds.forEach((round, index) => {
    round.round = Number(currentRound) - 1 - index
  })

  return rounds.slice(0, TARGET_ROUND_COUNT)
}

/** Reads past Winner events, grouped one row per draw, most recent first. */
export function useWinnerHistory() {
  const chainId = useChainId()
  const address = useLotteryAddress()
  const publicClient = usePublicClient()
  const { round } = useLotteryData()
  const deployBlock = getLotteryDeployBlock(chainId) ?? 0n

  const enabled = Boolean(address && publicClient && round !== undefined)

  return useQuery({
    queryKey: ['winnerHistory', chainId, address, deployBlock.toString(), round?.toString()],
    queryFn: () =>
      fetchWinnerRounds({
        publicClient: publicClient as PublicClient,
        address: address as Address,
        deployBlock,
        currentRound: round as bigint,
      }),
    enabled,
  })
}
