import { anvil, baseSepolia } from 'wagmi/chains'
import type { Address } from 'viem'

// NEXT_PUBLIC_* is inlined at build time, so each key must be a literal
// property access — it cannot be built dynamically from the chain id.
const LOTTERY_ADDRESSES: Record<number, Address | undefined> = {
  [anvil.id]: process.env.NEXT_PUBLIC_LOTTERY_ADDRESS_31337 as Address | undefined,
  [baseSepolia.id]: process.env.NEXT_PUBLIC_LOTTERY_ADDRESS_84532 as Address | undefined,
}

const LOTTERY_DEPLOY_BLOCKS: Record<number, bigint | undefined> = {
  [anvil.id]: toBigIntOrUndefined(process.env.NEXT_PUBLIC_LOTTERY_DEPLOY_BLOCK_31337),
  [baseSepolia.id]: toBigIntOrUndefined(process.env.NEXT_PUBLIC_LOTTERY_DEPLOY_BLOCK_84532),
}

function toBigIntOrUndefined(value: string | undefined): bigint | undefined {
  return value ? BigInt(value) : undefined
}

/** Returns the deployed Lottery address for a chain, or undefined if not deployed there yet. */
export function getLotteryAddress(chainId: number): Address | undefined {
  return LOTTERY_ADDRESSES[chainId]
}

/** Returns the block Lottery was deployed at on a chain, used to anchor event log scans. */
export function getLotteryDeployBlock(chainId: number): bigint | undefined {
  return LOTTERY_DEPLOY_BLOCKS[chainId]
}
