import { defineConfig } from '@wagmi/cli'
import { foundry } from '@wagmi/cli/plugins'

export default defineConfig({
  out: 'lib/generated.ts',
  plugins: [
    foundry({
      project: '../smart-contract',
      include: ['Lottery.sol/Lottery.json'],
      forge: { build: false },
    }),
  ],
})
