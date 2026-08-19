'use client'

import { AnimatePresence, motion } from 'framer-motion'

const STEPS = [
  {
    title: 'Pick a tier & buy a ticket',
    description: 'Choose $1, $5, or $10 priced live in ETH via a Chainlink price feed. Each ticket is one entry.',
  },
  {
    title: 'All tiers share one pool',
    description: 'Every ticket, from every tier, feeds the same prize pool.',
  },
  {
    title: 'A random draw picks winners',
    description: 'Chainlink VRF picks one winner per tier the more tickets you hold in a tier, the better your odds there.',
  },
  {
    title: 'Prizes split by tier',
    description:
      'The $1 tier wins 15%, $5 wins 35%, and $10 wins 50% of the pool. An empty tier’s share is redistributed to the tiers that had entries.',
  },
  {
    title: 'Get paid automatically',
    description:
      'Winnings are sent straight to your wallet. If that transfer ever fails, a Claim banner appears so you can pull it manually.',
  },
]

/** "How It Works" popup — explains the lottery mechanics, opened from the Navbar settings icon. */
export function HowItWorksModal({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) {
  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          className="fixed inset-0 z-60 flex items-center justify-center p-4"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: 0.15 }}
        >
          <div className="absolute inset-0 bg-black/00 backdrop-blur-sm" onClick={onClose} />

          <motion.div
            className="bg-[#030f1f] relative w-full max-w-md rounded-2xl sm:rounded-3xl border border-blue-500/20 p-6 sm:p-8 max-h-[85vh] overflow-y-auto"
            initial={{ opacity: 0, scale: 0.95, y: 10 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: 10 }}
            transition={{ duration: 0.2, ease: [0.16, 1, 0.3, 1] }}
          >
            <div className="flex items-center justify-between mb-5 sm:mb-6">
              <h2 className="text-lg sm:text-xl font-black tracking-tight text-white">How It Works</h2>
              <button
                type="button"
                onClick={onClose}
                aria-label="Close"
                className="p-1.5 rounded-lg text-gray-400 hover:text-white hover:bg-white/5 transition-colors"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <ol className="space-y-4 sm:space-y-5">
              {STEPS.map((step, index) => (
                <li key={step.title} className="flex gap-3">
                  <span className="shrink-0 w-6 h-6 rounded-full btn-color flex items-center justify-center text-[11px] font-bold text-white">
                    {index + 1}
                  </span>
                  <div>
                    <p className="text-sm font-bold text-white">{step.title}</p>
                    <p className="text-xs text-white/60 leading-relaxed mt-0.5">{step.description}</p>
                  </div>
                </li>
              ))}
            </ol>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}
