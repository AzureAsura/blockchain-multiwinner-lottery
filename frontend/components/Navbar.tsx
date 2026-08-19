'use client'

import { useState } from 'react'
import Link from 'next/link'
import Image from 'next/image'
import { HowItWorksModal } from '@/components/HowItWorksModal'
import { ConnectWalletButton } from '@/components/wallet/ConnectWalletButton'

const Navbar = () => {
  const [isHowItWorksOpen, setIsHowItWorksOpen] = useState(false)

  return (
    <>
    <nav className="fixed top-0 left-0 w-full z-50 transition-all card">
      <div className="px-4 md:px-0 md:w-[95vw] mx-auto rounded-xl py-4 flex items-center shadow-2xl">
        <div className="flex items-center justify-between w-full">
          {/* Logo Section */}
          <Link href={'/'} className="flex items-center gap-2 cursor-pointer group shrink-0">
            <Image src={'https://nirmala-finance-cpt.vercel.app/logo.svg'} alt='logo' height={35} width={35} priority />
            <div className="flex flex-col justify-between leading-none">
              <span className="text-[18px] font-black tracking-tighter text-white uppercase">
                Nirmala
              </span>
              <span className="text-[12px] font-bold tracking-[0.2em] text-blue-500 uppercase">
                Lottery
              </span>
            </div>
          </Link>

          <div className="hidden lg:flex items-center card p-1.5 rounded-2xl ">

            <button className="flex items-center gap-2 px-5 py-2 rounded-xl text-xs md:text-sm font-semibold text-white btn-color shadow-lg shadow-blue-500/20 transition-all">
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M15 5v2m0 4v2m0 4v2M5 5a2 2 0 00-2 2v3a2 2 0 110 4v3a2 2 0 002 2h14a2 2 0 002-2v-3a2 2 0 110-4V7a2 2 0 00-2-2H5z" />
              </svg>
              <span>Lottery</span>
            </button>

            <button className="flex items-center gap-2 px-5 py-2 rounded-xl text-xs md:text-sm font-semibold text-gray-400 hover:text-white transition-colors">
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <span>DEX</span>
            </button>

            <button className="flex items-center gap-2 px-5 py-2 rounded-xl text-xs md:text-sm font-semibold text-gray-400 hover:text-white transition-colors">
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
              </svg>
              <span>Crypto Price Tracker</span>
            </button>
          </div>

          <div className="flex items-center gap-3">
            <Link
              href="https://github.com/AzureAsura/blockchain-multiwinner-lottery"
              target="_blank"
              className="p-2.5 rounded-lg card text-white transition-all active:scale-95 shadow-sm "
            >
              <svg className="w-5 h-5 fill-current" viewBox="0 0 24 24">
                <path d="M12 0C5.37 0 0 5.37 0 12c0 5.31 3.435 9.795 8.205 11.385.6.105.825-.255.825-.57 0-.285-.015-1.23-.015-2.235-3.015.555-3.795-.735-4.035-1.41-.135-.345-.72-1.41-1.23-1.695-.42-.225-1.02-.78-.015-.795.945-.015 1.62.87 1.845 1.23 1.08 1.815 2.805 1.305 3.495.99.105-.78.42-1.305.765-1.605-2.67-.3-5.46-1.335-5.46-5.925 0-1.305.465-2.385 1.23-3.225-.12-.3-.54-1.53.12-3.18 0 0 1.005-.315 3.3 1.23.96-.27 1.98-.405 3-.405s2.04.135 3 .405c2.295-1.56 3.3-1.23 3.3-1.23.66 1.65.24 2.88.12 3.18.765.84 1.23 1.905 1.23 3.225 0 4.605-2.805 5.625-5.475 5.925.435.375.81 1.095.81 2.22 0 1.605-.015 2.895-.015 3.3 0 .315.225.69.825.57A12.02 12.02 0 0024 12c0-6.63-5.37-12-12-12z" />
              </svg>
            </Link>

            <ConnectWalletButton />

            <div className="flex items-center gap-1 text-gray-400">
              <button
                type="button"
                onClick={() => setIsHowItWorksOpen(true)}
                aria-label="How it works"
                className="p-2 rounded-lg hover:text-white hover:bg-white/5 transition-colors"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
                  <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
              </button>

              {/* <button className="p-2 rounded-lg hover:text-white hover:bg-white/5 transition-colors">
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                </svg>
              </button> */}
            </div>
          </div>

        </div>
      </div>
    </nav>

    <HowItWorksModal isOpen={isHowItWorksOpen} onClose={() => setIsHowItWorksOpen(false)} />
    </>
  )
}

export default Navbar