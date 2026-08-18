'use client'

import { useEffect, useState } from 'react'

// Matches Lottery.sol's `enum LotteryState { OPEN, CALCULATING }` ordering.
const LOTTERY_STATE_CALCULATING = 1

export type CountdownStatus = 'loading' | 'calculating' | 'awaiting-draw' | 'counting'

export type Countdown = {
  status: CountdownStatus
  secondsRemaining: number
}

/**
 * Ticks every second and reports time left until the next draw.
 * - `loading`: data not fetched yet.
 * - `calculating`: a draw is in progress (VRF requested, awaiting fulfillment).
 * - `awaiting-draw`: interval elapsed but Automation hasn't called performUpkeep yet.
 * - `counting`: normal countdown, see `secondsRemaining`.
 */
export function useCountdown(nextDrawTime: bigint | undefined, lotteryState: number | undefined): Countdown {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000))

  useEffect(() => {
    const id = setInterval(() => setNow(Math.floor(Date.now() / 1000)), 1_000)
    return () => clearInterval(id)
  }, [])

  if (nextDrawTime === undefined || lotteryState === undefined) {
    return { status: 'loading', secondsRemaining: 0 }
  }

  if (lotteryState === LOTTERY_STATE_CALCULATING) {
    return { status: 'calculating', secondsRemaining: 0 }
  }

  const secondsRemaining = Number(nextDrawTime) - now
  if (secondsRemaining <= 0) {
    return { status: 'awaiting-draw', secondsRemaining: 0 }
  }

  return { status: 'counting', secondsRemaining }
}
