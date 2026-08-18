import { formatEther } from 'viem'

/** Shortens an address/hash to "0x1234…abcd" for display. */
export function truncateAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`
}

/** Formats a wei amount as "X.XXXX ETH" for display. Not for calculations — Number() loses precision. */
export function formatEth(wei: bigint, decimals = 4): string {
  return `${Number(formatEther(wei)).toFixed(decimals)} ETH`
}

/** Formats an 18-decimal USD amount (as returned by getPoolBalanceUSD) as "$X,XXX.XX". Display-only. */
export function formatUsd(usd18: bigint): string {
  const value = Number(usd18) / 1e18
  return `$${value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

/** Formats a duration in seconds as "DD:HH:MM:SS". */
export function formatCountdown(totalSeconds: number): string {
  const clamped = Math.max(0, Math.floor(totalSeconds))
  const days = Math.floor(clamped / 86_400)
  const hours = Math.floor((clamped % 86_400) / 3_600)
  const minutes = Math.floor((clamped % 3_600) / 60)
  const seconds = clamped % 60
  const pad = (n: number) => n.toString().padStart(2, '0')
  return `${pad(days)}:${pad(hours)}:${pad(minutes)}:${pad(seconds)}`
}
