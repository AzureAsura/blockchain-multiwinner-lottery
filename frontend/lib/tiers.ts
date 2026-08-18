// Matches Lottery.sol's `enum Tier { ONE, FIVE, TEN }` ordering.
export type Tier = 0 | 1 | 2

export const TIER_LABELS: Record<Tier, string> = {
  0: '$1',
  1: '$5',
  2: '$10',
}
