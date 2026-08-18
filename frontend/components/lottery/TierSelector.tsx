'use client'

import { TIER_LABELS, type Tier } from '@/lib/tiers'

const TIERS: Tier[] = [0, 1, 2]

function TierChip({
  tier,
  entryCount,
  isSelected,
  onSelect,
}: {
  tier: Tier
  entryCount: bigint | undefined
  isSelected: boolean
  onSelect: (tier: Tier) => void
}) {
  return (
    <button
      type="button"
      onClick={() => onSelect(tier)}
      className={`flex flex-col items-center justify-center gap-0.5 w-16 h-14 sm:w-20 sm:h-16 rounded-lg sm:rounded-xl border transition-all shrink-0 ${
        isSelected
          ? 'btn-color border-blue-300/30 shadow-[inset_0_1px_0_rgba(255,255,255,0.15)]'
          : 'bg-white/5 border-white/10 hover:bg-white/10'
      }`}
    >
      <span className="font-black text-base sm:text-2xl text-white">{TIER_LABELS[tier]}</span>
      <span className="text-[8px] sm:text-[9px] text-white/50">
        {entryCount !== undefined ? `${entryCount.toString()} entries` : ''}
      </span>
    </button>
  )
}

export function TierSelector({
  selected,
  onSelect,
  entryCounts,
}: {
  selected: Tier
  onSelect: (tier: Tier) => void
  entryCounts: readonly [bigint | undefined, bigint | undefined, bigint | undefined]
}) {
  return (
    <div className="flex justify-center gap-2 sm:gap-3 bg-[#0E172A]/90 p-2 sm:p-2.5 rounded-xl sm:rounded-2xl border border-blue-500/30 backdrop-blur-md shadow-[0_4px_24px_rgba(59,130,246,0.35)] max-w-full">
      {TIERS.map((tier) => (
        <TierChip
          key={tier}
          tier={tier}
          entryCount={entryCounts[tier]}
          isSelected={selected === tier}
          onSelect={onSelect}
        />
      ))}
    </div>
  )
}
