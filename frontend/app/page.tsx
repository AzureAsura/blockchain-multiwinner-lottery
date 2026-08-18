'use client'

import { motion } from 'framer-motion'
import { HeroSection } from '@/components/HeroSection'
import { WinnerSection } from '@/components/WinnerSection'

const Page = () => {
  return (
    <div className="min-h-screen text-white font-sans flex flex-col items-center pt-24 pb-20 px-3 sm:px-4 md:px-0 md:w-[95%] mx-auto w-full max-w-full overflow-x-clip">
      <section className="w-full sticky top-24 z-10 max-w-full">
        <HeroSection />
      </section>

      <motion.section
        initial={{ y: 60, opacity: 0 }}
        whileInView={{ y: 0, opacity: 1 }}
        viewport={{ once: true, margin: '-20px' }}
        transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
        className="w-full -mt-10 sm:-mt-20 relative z-20 max-w-full"
      >
        <WinnerSection />
      </motion.section>
    </div>
  )
}

export default Page