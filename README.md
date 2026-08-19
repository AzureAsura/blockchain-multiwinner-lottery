# Nirmala Lottery

A multi-tier on-chain lottery on Base. Three ticket tiers priced in USD ($1 / $5 / $10) but paid in ETH, one shared prize pool, a random winner per tier picked by Chainlink VRF, and a Next.js frontend wired directly to the deployed contract — no backend, no indexer, no custody. Live on Base Sepolia testnet.

## How it works

1. Pick a tier ($1 / $5 / $10) and buy a ticket. The frontend quotes the current ETH price, but the contract re-checks the real Chainlink price feed on-chain at execution time — it never trusts a client-supplied number. Overpayment is refunded automatically in the same transaction.
2. All three tiers pay into one shared pool.
3. On a fixed schedule, the lottery requests randomness from Chainlink VRF v2.5 and picks one winner per tier that actually has entrants. If nobody entered that round, the round just resets — no VRF request spent.
4. The pool is split 15% / 35% / 50% across the $1 / $5 / $10 tiers. An empty tier's share is redistributed proportionally to the tiers that have entrants, and rounding dust always lands with the largest active tier, so nothing is ever left stuck in the contract.
5. Winners are paid automatically. If a winner's wallet can't receive the transfer (e.g. a broken contract wallet), that prize falls back to a claimable balance they can withdraw later — this never blocks the round or the other winners.

Full mechanics, security reasoning, and gas numbers: [`smart-contract/README.md`](smart-contract/README.md).

## Architecture

```
smart-contract/   Foundry + Solidity 0.8.29 — the contract itself
frontend/         Next.js 16 + wagmi/viem — reads and writes the contract directly
.github/          Scheduled workflow that drives the draw (see below)
docs/             Design history: PRD, wiring plan, testnet deploy log, automation notes
```

There is no backend server and no database. The frontend reads pool balance, round number, entry counts, and draw history straight from the chain (`getPoolBalanceETH`, `getRound`, `getEntryCount`, `Winner` event logs), and every write (`buyTicket`, `claimPrize`) goes through the user's own connected wallet.

## Draw automation

The contract exposes the standard `checkUpkeep` / `performUpkeep` pair, deliberately with **no access control** — any caller can trigger a draw once the interval has elapsed, by design. It was originally meant to be called by Chainlink Automation, but that service's testnet tier sunset in mid-2026 (and the next candidate, Gelato, turned out to have the same problem on its own platform migration). Draws are currently triggered by a scheduled GitHub Actions workflow instead ([`.github/workflows/lottery-upkeep.yml`](.github/workflows/lottery-upkeep.yml)) that checks `checkUpkeep` first and only sends a transaction when a draw is actually due, so idle polling costs nothing. Full rationale and the alternatives that were ruled out: [`docs/AUTOMATION.md`](docs/AUTOMATION.md).

## Tech stack

- **Contract**: Foundry, Solidity 0.8.29, Chainlink VRF v2.5 (subscription, native-ETH payment), Chainlink Price Feeds, Chainlink Automation-compatible interface
- **Frontend**: Next.js 16, React 19, wagmi + viem, RainbowKit, TanStack Query, Tailwind CSS 4, framer-motion
- **Target chain**: Base (currently deployed on Base Sepolia testnet; Anvil supported for local dev)

## Getting started

### Smart contract

```shell
cd smart-contract
forge install
forge build
forge test -vvv
```

64 tests pass, 100% line/branch/function coverage on `src/`. Full local (Anvil) and testnet (Base Sepolia) deployment steps: [`smart-contract/README.md`](smart-contract/README.md).

### Frontend

```shell
cd frontend
npm install
npm run dev
```

Needs a `.env.local` — copy `frontend/.env.example` and fill in RPC URLs and the deployed contract address for whichever network you're pointing at (Anvil or Base Sepolia). ABI types are generated from the compiled contract via `npm run wagmi` (requires `forge build` to have run first in `smart-contract/`).

## Project history

The `docs/` folder keeps the actual design and deployment log, not just a spec written before the fact:

- [`docs/PRD.md`](docs/PRD.md) — original product requirements (in Indonesian)
- [`docs/PLAN.md`](docs/PLAN.md) — plan for wiring the frontend to the deployed contract
- [`docs/TESTNET.md`](docs/TESTNET.md) — Base Sepolia deployment log
- [`docs/AUTOMATION.md`](docs/AUTOMATION.md) — why Chainlink Automation and Gelato were dropped in favor of a GitHub Actions cron
- [`docs/NOTE.md`](docs/NOTE.md) — non-coding checklist (accounts, funding, keys) for anyone redeploying this
