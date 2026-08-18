'use client'

import React, { useState } from 'react'
import Image from 'next/image'
import { useLotteryData } from '@/hooks/useLotteryData'
import { formatEth, formatUsd } from '@/lib/format'
import type { Tier } from '@/lib/tiers'
import { BuyTicketButton } from './lottery/BuyTicketButton'
import { ClaimPrizeBanner } from './lottery/ClaimPrizeBanner'
import { TierSelector } from './lottery/TierSelector'

export const HeroSection = () => {
    const [tier, setTier] = useState<Tier>(0)
    const { poolBalanceEth, poolBalanceUsd, round, entryCounts } = useLotteryData()

    return (
        /* 1. Tambah min-h-[500px] atau min-h-screen-1/2 khusus mobile di container utama */
        <div className="relative w-full max-w-full rounded-2xl sm:rounded-4xl p-5 sm:p-10 overflow-hidden shadow-white min-h-[520px] sm:min-h-0 flex flex-col justify-between">

            {/* Background Image */}
            <Image
                src="/aboutabout.webp"
                alt="Banner Background"
                fill
                priority
                className="object-cover object-center pointer-events-none z-0"
            />

            <div className="absolute inset-0 bg-black/60 pointer-events-none z-0" />

            <div className="text-center relative z-10 mt-16">
                <p className="text-[11px] sm:text-sm font-bold tracking-wider uppercase mb-1.5">
                    Prize pool
                </p>
                <h1 className="text-5xl sm:text-8xl font-black tracking-tight text-white drop-shadow-[0_6px_20px_rgba(255,255,255,0.4)] break-words mt-1">
                    {poolBalanceUsd !== undefined ? formatUsd(poolBalanceUsd) : '…'}
                </h1>

                <div className="flex items-center justify-center gap-2 mt-2 sm:mt-3 text-xs sm:text-sm font-semibold  tracking-wide">
                    <div className="flex items-center gap-1.5">

                        <svg className="w-3.5 h-3.5 sm:w-4 sm:h-4 fill-current" viewBox="0 0 320 512">
                            <path d="M311.9 260.8L160 353.6 8 260.8 160 0l151.9 260.8zM160 383.4L8 290.6 160 512l152-221.4-152 92.8z" />
                        </svg>
                        <span>{poolBalanceEth !== undefined ? formatEth(poolBalanceEth) : '…'}</span>
                    </div>
                    <span className="">•</span>
                    <span className="uppercase tracking-wider font-bold">
                        {round !== undefined ? `Draw #${round}` : 'Draw —'}
                    </span>
                </div>

                <BuyTicketButton tier={tier} />
            </div>

            <div className="w-full h-56 md:h-48 my-4 sm:my-2 flex items-center justify-center relative z-10">
                <ClaimPrizeBanner />
            </div>

            {/* Participate Button & Numbers Display */}
            <div className="flex flex-col items-center relative z-10 gap-3 pb-12 sm:pb-12 w-full max-w-full">
                <TierSelector selected={tier} onSelect={setTier} entryCounts={entryCounts} />
            </div>

            {/* Left Bottom "How it works" */}
            {/* <div className="absolute left-6 bottom-20 max-w-xs text-xs text-purple-200/80 hidden md:block z-10">
                <div className="flex items-center gap-1.5 mb-1.5 font-semibold text-purple-200">
                    <span className="w-4 h-4 rounded-full border border-purple-300 flex items-center justify-center text-[10px] font-bold">
                        ?
                    </span>
                    How it works
                </div>
                <p className="leading-relaxed font-normal text-[11px] text-purple-200/70">
                    The more funds you deposit into your account at once, the more tickets you will receive!
                </p>
            </div> */}
        </div>
    )
}