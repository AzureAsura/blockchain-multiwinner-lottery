# Lottery Smart Contract

A tiered on-chain lottery built with Foundry, using Chainlink VRF v2.5 for randomness, Chainlink Automation for scheduled draws, and Chainlink Price Feeds for USD-priced tickets. Target chain: Base.

## How it works

There are 3 ticket tiers, priced in USD but paid in ETH: `$1`, `$5`, `$10`. A buyer picks a tier and pays ETH. The contract does not trust any price a frontend quotes it: at the moment `buyTicket` executes, it reads the current ETH/USD price from a Chainlink Price Feed itself, computes the required wei amount, and checks the payment against that. If the buyer sent more than required, the difference is refunded automatically in the same transaction. All 3 tiers pay into one shared prize pool.

Draws are time based and fully automatic. Chainlink Automation calls `checkUpkeep` periodically off-chain; once the configured interval has elapsed and the lottery is open, it calls `performUpkeep` on-chain. If nobody entered that round, the round is simply reset (no VRF request spent, so no gas or subscription funds are wasted on a draw with no possible winner). If there are entrants, the contract requests 3 random words from Chainlink VRF v2.5 in a single call, funded from a subscription in native ETH (no LINK token needed). One random word is used per tier. While a draw is in progress the lottery state moves to "calculating" and new ticket purchases are rejected, closing the window between requesting randomness and receiving it so nobody can time a purchase around the draw.

When Chainlink VRF responds, the contract picks one winner per tier (whichever tiers actually have entrants) and splits the pool 15% / 35% / 50% across tiers `$1` / `$5` / `$10`. If a tier has no entrants, its percentage is redistributed proportionally across the tiers that do, not split evenly. Because percentages don't divide the pool evenly in general, the tier with the largest active share is deliberately paid last, as whatever is left over after paying the other tiers, rather than its own separately rounded share, so the three prizes always add up to exactly the pool with nothing left behind in the contract.

Paying winners is a two step, "push then fall back to pull" design. The contract first tries to send each winner their ETH directly, with a fixed, small gas stipend on that transfer. If a winner cannot receive it (for example, a contract wallet with no `receive` function, or one that intentionally reverts), that specific prize is credited to a claimable balance instead of blocking anything. Nothing else about the draw depends on that transfer succeeding: the round is already fully reset (pool zeroed, next round started, state back to open) before any payout is attempted, so one bad winner can never get the other winners' payouts stuck, and can never block the next round from starting. A winner whose payout fell back to a claimable balance can withdraw it later by calling `claimPrize`, which also follows the same pattern: state is zeroed before the transfer, so a malicious contract cannot re-enter `claimPrize` to drain it twice, and this is proven directly in the test suite, not just argued.

## Contract addresses and constants

- Ticket prices (fixed): `$1`, `$5`, `$10`.
- Prize split (fixed): 15% / 35% / 50% for tiers `$1` / `$5` / `$10` respectively.
- Random words per draw: 3 (one per tier), requested from VRF v2.5 using native ETH payment.
- Payout gas stipend: 30,000 gas per winner push attempt.
- No admin, owner, or pause functions exist beyond one inherited from Chainlink's VRF base contract, which only lets the deployer migrate to a new VRF coordinator if Chainlink ever requires it. There is no function that can withdraw funds, change ticket prices, change the prize split, or halt the lottery. This was a deliberate choice: every admin-controlled parameter is both an attack surface and a piece of centralized trust, and none were requested by the product spec, so none were added "just in case."

## Project structure

```
smart-contract/
  src/
    Lottery.sol            Main contract
    PriceConverter.sol     USD/ETH conversion library, Chainlink price feed guard
  script/
    HelperConfig.s.sol     Per-network deployment config
    Interactions.s.sol     CreateSubscription / FundSubscription / AddConsumer
    DeployLottery.s.sol    Deploys Lottery against an already-funded VRF subscription
  test/
    *.t.sol                Unit, fuzz, integration, and attack-vector tests
    invariant/              Handler-based invariant test (solvency)
```

## Setup

```shell
forge install
```

## Build

```shell
forge build
```

## Test

```shell
forge test -vvv
forge coverage --report summary
```

The suite currently has 63 passing tests: unit tests for every function's happy path and revert path, fuzz tests on numeric inputs (thousands of runs each), full-round integration tests spanning purchase through payout, an invariant test that fuzzes 128,000 random buy/draw/claim actions and checks the contract's ETH balance never falls short of what it owes anyone, and a dedicated set of tests written directly against independently researched attack vectors (entry locking during a draw, VRF callback access control, gas cost staying flat regardless of entrant count, reentrancy through ticket refunds, and what happens if a VRF subscription runs dry). `src/Lottery.sol` and `src/PriceConverter.sol` are both at 100% line, statement, branch, and function coverage.

## Format

```shell
forge fmt
forge fmt --check
```

## Gas snapshot

```shell
forge snapshot
```

Measured costs (median, from the current test suite): buying a ticket costs about 118,000 gas, claiming a fallen-back prize costs about 30,000 gas, and a full draw callback costs roughly 61,000 gas for a single winner up to about 137,000 gas when all 3 tiers have entrants (winner selection is a direct array index computed from the random word, not a loop, so this cost does not grow with how many people bought tickets). On Base, whose gas price is typically a small fraction of a gwei, these translate to a fraction of a cent per transaction in practice; the absolute gas numbers above matter less than the fact that they stay flat as usage grows.

## Known limitation: VRF subscription running dry between request and fulfillment

On the Chainlink VRF mock used in local testing, the subscription's balance is validated when a request is fulfilled, not when it is requested. That means `performUpkeep` can succeed and lock the round into "calculating" even against an empty or soon to be empty subscription, and if the subscription cannot cover the request by the time Chainlink attempts to fulfill it, that fulfillment fails and the round has no way to recover on its own: `performUpkeep` refuses to run again while a draw is in progress, and only the VRF coordinator itself can call the fulfillment function. Whether the real, non-mock VRF v2.5 coordinator enforces the balance check earlier (at request time) was not independently confirmed either way.

This is treated as an accepted operational risk rather than a code defect: the mitigation is keeping the subscription funded with comfortable headroom, the same operational discipline any VRF-based contract needs regardless of this specific behavior. A stricter guard (checking the subscription's on-chain balance before every request) was considered and deliberately not added, since it adds an extra external call and complexity to every single draw to protect against an operator error that monitoring already covers more simply.

## Local deployment (Anvil)

Chainlink's VRF mock derives a new subscription's ID from `blockhash`, which differs between a `forge script` simulation pass and the real sequential broadcast, so a subscription created and immediately used within one script run ends up referencing an ID that was never actually created on chain. This was confirmed directly (not assumed) by comparing a script's own reported subscription ID against the ID actually emitted in the real transaction's event log, which did not match. The practical consequence is that local subscription setup has to be its own separate step, with the real ID read back from the transaction receipt rather than trusted from the script's own console output, before it gets used anywhere else.

```shell
anvil
# in another terminal, on a fresh chain:
cast rpc evm_mine --rpc-url http://127.0.0.1:8545   # move past block 0, or subscription creation reverts

forge script script/Interactions.s.sol:CreateSubscription \
  --rpc-url http://127.0.0.1:8545 --private-key <anvil-key> --broadcast
# read the real subscription id from the broadcast receipt's SubscriptionCreated event
# (broadcast/Interactions.s.sol/31337/run-latest.json), and note the deployed
# VRFCoordinatorV2_5Mock / MockV3Aggregator addresses from the same file

VRF_COORDINATOR=<addr> PRICE_FEED=<addr> SUBSCRIPTION_ID=<real subId> \
  forge script script/DeployLottery.s.sol:DeployLottery \
  --rpc-url http://127.0.0.1:8545 --private-key <anvil-key> --broadcast
```

The `VRF_COORDINATOR` and `PRICE_FEED` overrides point the second command at the exact mock contracts the first command deployed, instead of `HelperConfig` deploying a brand new, unrelated pair that knows nothing about the subscription just created.

This whole two-step dance is a local-testing-only concern. On a real network, a subscription is created once (through the Chainlink UI, see below) and reused for every deployment after that, so a real deployment never needs to create a subscription and use it in the same script run at all.

## Testnet deployment (Base Sepolia)

1. Create and fund a VRF v2.5 subscription at [vrf.chain.link](https://vrf.chain.link), using native ETH funding rather than LINK, since the contract requests randomness with native payment. This is a one-time step; the same subscription is reused for every future deployment of this contract.
2. Copy `.env.example` to `.env` and fill in `BASE_SEPOLIA_RPC_URL` and, if verifying the contract on-chain, `BASESCAN_API_KEY`.
3. Import a deployer wallet's private key into Foundry's encrypted keystore rather than putting it in `.env` in plain text:
   ```shell
   cast wallet import lottery-deployer --interactive
   ```
4. Deploy, passing the subscription ID created in step 1:
   ```shell
   SUBSCRIPTION_ID=<id from vrf.chain.link> forge script script/DeployLottery.s.sol:DeployLottery \
     --rpc-url $BASE_SEPOLIA_RPC_URL --account lottery-deployer --broadcast --verify
   ```
5. Add the newly deployed contract as a consumer on the subscription. `DeployLottery` does this automatically as its last step, so this is usually already done; it only needs repeating manually if a later redeployment needs to be pointed at the same subscription.

The ETH/USD price feed and VRF coordinator and key hash addresses for Base Sepolia are already filled in `script/HelperConfig.s.sol`. The VRF coordinator and key hash were pulled directly from Chainlink's official documentation and their format (address and hash length) was checked. The price feed address was supplied by the project owner directly rather than independently verified against Chainlink's documentation at the time it was added, so it is worth confirming on Basescan Sepolia that it resolves to a genuine Chainlink ETH/USD aggregator before funding anything beyond disposable testnet ETH through it.
