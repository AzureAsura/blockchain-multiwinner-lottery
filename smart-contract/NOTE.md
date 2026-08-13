# Development Notes

Rationale and design notes that don't belong as inline comments in the contracts (kept to max 1-line comments there). Organized by file/step.

## PriceConverter.sol

- `PRICE_FEED_DECIMALS` is hardcoded to 8 rather than read via `feed.decimals()` — every Chainlink USD price feed uses 8 decimals, so this holds universally and avoids an extra external call.
- `getEthUsdPrice` reverts on `answer <= 0` (`Lottery__InvalidPrice`) and on data older than `staleAfter` (`Lottery__StalePrice`), so a malfunctioning or manipulated oracle can't silently mis-price tickets.
- Lint suppressions:
  - `block-timestamp` on the staleness check — the comparison against `block.timestamp` *is* the staleness check; that's expected, not a bug.
  - `unsafe-typecast` on `uint256(answer)` — safe because `answer > 0` is checked immediately above, so the cast can't change the value.
- `usdToWei` rounds down (integer division). Precision loss per fuzz-proven invariant (`testFuzz_usdToWei_roundTripPrecision`) is always less than one USD unit of price — negligible at wei scale, never overcharges.

## PriceConverterTest.t.sol

- `callGetEthUsdPrice()` is a thin external wrapper used only so `vm.expectRevert` latches onto the right call boundary. Library `internal` functions are inlined into the caller, so calling `PriceConverter.getEthUsdPrice(...)` directly means `vm.expectRevert` catches the *inner* staticcall to the price feed (which succeeds) instead of the revert that happens afterward in the same frame. Routing through `this.callGetEthUsdPrice()` gives `expectRevert` an actual CALL boundary to catch.

## Lottery.sol (Step 2 skeleton)

- `Lottery__ZeroAddress` guards only `priceFeed` in the constructor — `vrfCoordinator` is already guarded by the inherited `VRFConsumerBaseV2Plus.ZeroAddress()`, no need to duplicate it.
- `s_prizePool` (not `address(this).balance`) is the pool source of truth from the start, since payouts will later leave unclaimed prizes sitting in the contract balance across rounds (hybrid push/claim, added in Step 6).
- `i_keyHash`, `i_subscriptionId`, `i_callbackGasLimit` aren't read by anything yet — nothing in Step 2 exercises them, so they're only verifiable once Step 4/6 wire them into `requestRandomWords`. No getter was added solely to unit-test storage; that would be surface added for testing's sake, not for the product.
- `fulfillRandomWords` is a required override from `VRFConsumerBaseV2Plus` (abstract) with an intentionally empty body — real payout logic lands in Step 6.
- Constructor-revert tests (`test_constructor_reverts*`) call `new Lottery(...)` directly/via a private `_deploy` helper — no `vm.expectRevert` wrapper-boundary issue there, since `CREATE` is always its own call frame, unlike the inlined-library gotcha in `PriceConverterTest.t.sol`.

## Lottery.sol (Step 3 — buyTicket)

- `buyTicket` follows CEI: entry push + pool credit + event happen before the refund's external call, so a reentrant call from a malicious refund recipient is just a legitimate second purchase — no `nonReentrant` needed.
- Refund failure reverts the whole purchase (`Lottery__RefundFailed`), unlike prize payouts in Step 6 which fall back to a claimable balance instead of reverting — the difference is blast radius: a failed ticket refund only affects the buyer themselves (safe to let them retry), while a failed draw payout would block every other participant's round if it reverted.
- No enum-range validation needed on the `tier` param — Solidity's calldata ABI decoder already reverts on out-of-range enum values for external function parameters.

## LotteryTest.t.sol (Step 3)

- `_forceState` uses `forge-std`'s `stdStore` to set `s_lotteryState` to `CALCULATING` without adding a test-only setter to production code. Still used in Step 4 tests too, for isolating `performUpkeep`'s own `Lottery__NotOpen` guard from its interval guard.
- `RejectingReceiver` (no `receive`/`fallback`) exists purely to test that a failed refund reverts the purchase (`Lottery__RefundFailed`).

## Lottery.sol (Step 4 — Automation)

- `checkUpkeep` intentionally ignores participant count (PRD: draw is purely time-based, no minimum-entries requirement) — it only checks `state == OPEN` and elapsed interval. The "skip if empty" decision happens inside `performUpkeep`, not here.
- `performUpkeep` re-validates state and interval itself rather than trusting `performData` — it's `external` with no access control by design (any address can call it, matching how Chainlink Automation nodes call it), so the guards must be self-sufficient.
- When there are no entries, `s_lastDrawTimestamp` is still advanced (and `DrawSkipped` emitted) instead of leaving it untouched — otherwise the first ticket buyer after a long quiet period would trigger an immediate draw, since the elapsed time already exceeds the interval.
- `Lottery__NotOpen` is reused from Step 3 for `performUpkeep`'s state guard rather than adding a new error — same underlying condition.

## LotteryTest.t.sol (Step 4)

- `_deployWithMockCoordinator` exists because the suite's default `VRF_COORDINATOR` is a dummy address with no code — fine for every test so far, but `performUpkeep`'s happy path now makes a real call to `requestRandomWords`, which needs an actual `VRFCoordinatorV2_5Mock` with a funded, consumer-registered subscription.
- `test_performUpkeep_requestsVrfWhenEntriesExist` expects `DrawRequested(1)` — safe to hardcode since each test deploys its own fresh coordinator, whose request IDs start at 1.

## Lottery.sol (Step 5 — prize math)

- `_calculatePrizes` takes `bool[3] tierActive`, not entry counts — the prize split is by fixed weight only, never by how many entries a tier has, so counts would be a misleading parameter shape.
- The last-tier-absorbs-the-remainder technique guarantees `sum(prizes) == pool` *by construction*, not just empirically — every non-largest tier's prize is a floor'd fraction, and the largest tier's prize is defined as whatever's left over. The 10,000-run fuzz test confirms it holds in practice (and that the subtraction never underflows).
- The `totalActiveWeight == 0` (all tiers inactive) branch returns zero prizes rather than reverting. In production this can't actually happen — `performUpkeep` never starts a draw with zero entries — but a `pure` helper has no caller-side access control, so it's guarded directly rather than trusted to never see that input.
- `_calculatePrizes` is `internal` (not `private`) specifically so `test/LotteryPrizeMathTest.t.sol`'s `LotteryHarness` can expose and fuzz it directly, without needing the full VRF callback (Step 6) to exist first.

## Lottery.sol (Step 6 — fulfillRandomWords + hybrid payout)

- Winner selection, prize math, and all round-reset state changes happen before any ETH leaves the contract (CEI) — a winner's payout failing can only affect that winner's own prize (falls to `s_claimablePrize`), never the round-reset or other winners' payouts.
- `_payout`'s `.call{gas: PAYOUT_GAS_STIPEND}` caps the gas a malicious/broken winner contract can burn to 30k — worst case across 3 winners is a bounded ~90k, not unbounded.
- Zero-prize winners (possible only when the pool is small enough that a non-largest tier's floor'd share rounds to 0) still get a `Winner` event, but `_payout` is skipped for them — no point risking/spending gas on a 0-value transfer.

## LotteryTest.t.sol (Step 6)

- Two real test-setup bugs surfaced while writing this suite (not contract bugs): (1) `vm.deal`ing a `RejectingReceiver` before calling `rejector.buy{value: x}(...)` double-funds it — the ETH sent with that call already comes from the *caller's* (the test contract's) own balance, so the dealt amount just sits unused and corrupts later balance assertions. Fixed by dropping the redundant `vm.deal` calls (here and in the Step 3 refund test). (2) Warping forward a full `INTERVAL` to trigger a draw leaves the mock price feed's `updatedAt` stale relative to the new `block.timestamp`; any post-warp `buyTicket` needs `feed.updateAnswer(...)` called again first to refresh it.
- `_warpAndPerformUpkeep` assumes `performUpkeep` is only ever called once per fresh coordinator in a given test (so the resulting VRF request ID is always 1) — same assumption already relied on in the Step 4 tests.

## Lottery.sol (Step 7 — claimPrize)

- Unlike `_payout`'s hybrid fallback (Step 6), `claimPrize` reverts outright on transfer failure (`Lottery__ClaimFailed`) rather than trying another fallback layer — a failed claim only affects the caller themselves, so there's no "block everyone else" risk to design around, and reverting also means the zeroed-out balance is rolled back, leaving the claim intact for a retry.
- CEI (zero `s_claimablePrize[msg.sender]` before the external call) is what makes the reentrancy test pass: a reentrant `claimPrize()` call sees a balance of 0 and reverts, so it can never double-spend — proven directly, not just argued.

## LotteryTest.t.sol (Step 7)

- `ReentrantClaimer.receive()` re-enters via a low-level `.call(...)` rather than calling `i_lottery.claimPrize()` directly — a direct call would bubble its revert up through `receive()`, which would in turn fail the *outer* legitimate transfer too, testing "everything reverts" instead of the actual property of interest ("the reentrant attempt specifically fails while the first claim still succeeds").
- `_setClaimable` uses `stdStore` to seed a claimable balance directly, skipping a full draw — `claimPrize`'s own logic doesn't depend on how the balance got there, and the draw path that produces it is already covered in Step 6's tests.

## Step 8 — Deploy scripts

**Address provenance:** VRF v2.5 coordinator + key hash for Base Sepolia are from `docs.chain.link/vrf/v2-5/supported-networks` (fetched directly, hex length-verified: 40 chars for the coordinator address, 64 for the key hash). The ETH/USD price feed address (`0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1`) was supplied directly by the project owner, not independently verified by the assistant (an automated lookup wasn't able to confirm it before the owner intervened) — **double-check this address on Basescan Sepolia before funding it with anything beyond disposable testnet ETH.**

**`createSubscription()`'s return value cannot be trusted across a `forge script --broadcast` run.** This cost significant debugging time, so recording it in full:

`VRFCoordinatorV2_5Mock.createSubscription()` derives the new subscription ID from `keccak256(abi.encodePacked(msg.sender, blockhash(block.number - 1), address(this), nonce))`. `forge script` works by simulating the entire `run()` once (to determine which calls to broadcast), then replaying exactly those calls, in order, against the real chain. Because `blockhash(block.number - 1)` differs between the simulation pass and the real sequential broadcast, the subId computed during simulation — and therefore baked into the calldata of any *later* broadcasted call that uses it (`fundSubscriptionWithNative`, `addConsumer`, a constructor arg) — does not match the subId actually created on-chain. The result is `InvalidSubscription()` reverts on those later calls.

Verified empirically (not just reasoned about) across 5 variations before concluding this is unavoidable within a single script run: inlining everything in one `vm.startBroadcast()` block, using `--slow`, and re-reading the ID via a fresh `getActiveSubscriptionIds()` view call mid-script all still failed the same way — because every one of those still evaluates within the same single simulation pass. The only reliable way to get the *real* subId is to read the `SubscriptionCreated` event from the transaction's actual receipt after a real broadcast (`cast receipt <tx hash>`), never from the script's own console/return output.

**Consequence for the scripts:** `DeployLottery.s.sol` no longer tries to auto-create-and-immediately-use a subscription. It requires one to already exist (`SUBSCRIPTION_ID` env var, or a nonzero `config.subscriptionId` from `HelperConfig` — e.g. once you've created one on Base Sepolia via vrf.chain.link). This actually matches real-world VRF usage: you create+fund a subscription once, then can (re)deploy consumer contracts against it many times.

**Local Anvil verification workflow** (two separate commands, matching the constraint above):
```bash
anvil                                   # in one terminal
cast rpc evm_mine --rpc-url http://127.0.0.1:8545   # VRFCoordinatorV2_5Mock's createSubscription() underflows at block 0 (blockhash(block.number - 1)); mine past genesis first

forge script script/Interactions.s.sol:CreateSubscription --rpc-url http://127.0.0.1:8545 --private-key <anvil-key> --broadcast
# Read the real subId from the broadcast receipt's SubscriptionCreated event (2nd topic), e.g.:
#   cat broadcast/Interactions.s.sol/31337/run-latest.json   (find the createSubscription() receipt's logs[0].topics[1])
#   cast --to-dec <that topic>
# Also note the deployed VRFCoordinatorV2_5Mock / MockV3Aggregator addresses from the same file.

VRF_COORDINATOR=<addr> PRICE_FEED=<addr> SUBSCRIPTION_ID=<real subId> \
  forge script script/DeployLottery.s.sol:DeployLottery --rpc-url http://127.0.0.1:8545 --private-key <anvil-key> --broadcast
```
`VRF_COORDINATOR`/`PRICE_FEED` env vars (read in `HelperConfig.getOrCreateAnvilConfig`) exist specifically so the second command reuses the *same* mock deployment instead of `HelperConfig` deploying a fresh, unrelated coordinator (which has no knowledge of the subscription created in step one).

This exact flow was run end-to-end against a live local Anvil and independently verified by querying the deployed contract afterward (`getLotteryState`, `getTicketPriceInWei`, `getNextDrawTime` via `cast call`, and `getSubscription` on the coordinator to confirm the Lottery address is a registered consumer) — not just "the script exited 0."

## Step 9 — Integration + invariant tests

- `LotteryIntegrationTest.t.sol` reuses the same "warp then re-refresh the mock feed, in that order" fix from Step 6/NOTE — worth restating since it's easy to get backwards again in a new file (update-then-warp leaves the feed stale relative to the new timestamp).
- The all-three-tiers integration test picks `randomWords[2] = 1` deliberately (not 0) specifically to prove the TEN-tier winner-selection modulo picks the *second* entrant, not just always the first — a fuzz seed of all zeros would pass even with an off-by-one indexing bug.
- `LotteryHandler` targets only itself (`targetContract(address(handler))`), not `Lottery` directly — this is the standard pattern so the fuzzer only calls through curated, bounded actions (buy/performUpkeep/fulfill/claim) instead of arbitrary raw calls with nonsensical inputs.
- `RejectingActor` (no receive/fallback) is one of five actors specifically so the invariant fuzzing exercises the claimable-fallback path, not just the happy path — otherwise `s_claimablePrize` would stay empty for the whole run since plain `makeAddr` EOAs always accept ETH.
- `s_pendingRequestId` is a ghost variable tracked via `vm.recordLogs()` reading the real `DrawRequested` event — necessary because the coordinator's request IDs increment across multiple draws in one fuzz run, so a hardcoded `1` (fine for single-draw tests elsewhere) would be wrong here.
- The `buyTicket` handler action deals ETH to `address(this)` (the handler) when the buyer is `RejectingActor`, but to the buyer directly for plain EOAs — same underlying mistake as the Step 6 `RejectingReceiver` bug: value sent via `{value: x}` must be dealt to whichever address is *making* that specific call, not the logical "buyer".
- `invariant_solvency` asserts `>=`, not `==` — `Lottery` has no `receive()`/`fallback()`, so no ETH can land in it outside `buyTicket`'s accounted flow, meaning equality happens to hold in practice, but `>=` is the actual safety property that matters (the contract must never fall short of what it owes) and is what the PRD's "no dust left behind" concern is really about avoiding failure of.
- Verified for real, not just "test passed": 256 runs × up to 500 calls/run = 128,000 total handler calls (roughly 32,000 each of buy/performUpkeep/fulfill/claim), 0 invariant violations, 0 unexpected reverts.

## Step 10 — Security pass & final report

**Build/test/format** (`forge build --force`, `forge test -vvv`, `forge fmt --check`): all clean. 58/58 tests pass, 0 compiler/lint warnings.

**Coverage** (`forge coverage --report summary`): `src/Lottery.sol` and `src/PriceConverter.sol` are both **100%** lines/statements/branches/functions. The reported project-wide total (72.84% lines) is dragged down by `script/*.s.sol` showing 0% — expected, since deploy scripts aren't exercised by `forge test` at all; they were verified separately via real `forge script --broadcast` runs against a live local Anvil in Step 8 (see that section above), which coverage tooling can't see.

**Gas** (`forge snapshot` + trace inspection, since `fulfillRandomWords` is `internal` and doesn't get its own line in `--gas-report`):
- `buyTicket`: min 23,793 / avg 116,673 / median 118,085 (273 calls, includes the 256-run fuzz test).
- `claimPrize`: min 23,528 / avg 28,900 / median 30,369 / max 35,238 (6 calls).
- `fulfillRandomWords` (measured via `Lottery::rawFulfillRandomWords` in call traces, since forge's function-level report only tracks calls made directly by the test contract): 58,706 gas for 1 winner whose payout fails and falls to claimable; 61,263 for 1 winner paid successfully; 97,644 for 2 winners paid; 136,825 for all 3 tiers paid — roughly +35–40k gas per additional active tier.

This **supersedes** the rough opcode-level estimate given earlier in chat (~12k push vs ~22k pull SSTORE) — those numbers were explicitly flagged as unmeasured at the time. The real numbers still support the same directional conclusion, more precisely: a successful push (single winner) costs 61,263 gas in one transaction, funded by the VRF subscription; the fallback path costs 58,706 gas in the draw *plus* a separate `claimPrize` call at 23,528–35,238 gas paid by the winner — so pull-style total cost (~85k–94k gas across 2 transactions) is clearly higher than push succeeding in one shot, confirming hybrid was the right call for the common case.

**Slither**: not installed in this environment (`slither: command not found`). Not run — flagged explicitly rather than silently skipped, per project policy. Offered to install; not requested, so static analysis coverage here relies on `forge lint` (built into `forge build`, already clean) plus the manual checklist below.

**Security checklist** (CLAUDE.md, walked against the final code):
- Reentrancy: all three ETH-transferring functions (`buyTicket`, `claimPrize`, `_payout`) follow CEI; proven directly via the Step 7 reentrancy test, not just argued.
- Access control: `performUpkeep` is deliberately open (anyone can call, matching real Chainlink Automation) but self-validates state+interval every call; `fulfillRandomWords` is gated by the inherited `rawFulfillRandomWords`'s coordinator-only check; no admin-only functions exist at all.
- Unchecked arithmetic: zero `unchecked` blocks anywhere in `src/` (verified via `grep`) — every arithmetic op relies on Solidity 0.8's default over/underflow checks.
- External calls: every `.call()` checks `success`; no loop ever iterates over a `s_entries` array (winner selection is O(1) via modulo indexing), so entry-array size can't be used to grief gas costs.
- Oracle: Chainlink Price Feed with staleness + non-positive guards, not a manipulable spot AMM price.
- Upgradeability: N/A, contract is deliberately not upgradeable.
- Emergency pause: **deliberately not implemented** — raised explicitly to the user as a checklist item (this contract does hold user funds) rather than silently deciding either way; user confirmed no pause wanted for the current scope, matching the original PRD (no admin powers requested) and CLAUDE.md's anti-overengineering guidance.

## LotterySecurityTest.t.sol — tests mapped to docs/ATTACK.md

The user researched common smart-contract attack vectors independently (`docs/ATTACK.md`) after Step 10 wrapped. Cross-checked each point against the final contract; most were already mitigated by earlier design decisions but lacked a test *proving* it. Five gaps were closed:

1. **Entry-lock window (ATTACK.md #1)** — `performUpkeep` sets `s_lotteryState = CALCULATING` *before* calling `requestRandomWords`, so there's no window between request and fulfillment where `buyTicket` would still succeed. Now proven with a real `performUpkeep` call (not `_forceState`) followed by an attempted purchase.
2. **Callback access control (ATTACK.md #1)** — already enforced by the inherited `rawFulfillRandomWords`'s coordinator-only check; now our own test proves a random caller can't spoof the coordinator and pick winners directly.
3. **O(1) gas scaling (ATTACK.md #19)** — winner selection is `randomWords[i] % count` array indexing, never a search loop, so `fulfillRandomWords` gas cost shouldn't scale with entrant count. Proven by comparing 1 entrant vs. 400 entrants in the same tier: gas differs by well under the 10,000 tolerance used, not the ~35k+/entry a real O(n) loop would show.
4. **Subscription running dry (ATTACK.md #4) — real finding, not just a mitigated checklist item.** On `VRFCoordinatorV2_5Mock`, balance is validated in `_chargePayment`, called from *fulfillment* (`fulfillRandomWords`/`fulfillRandomWordsWithOverride`), not from `requestRandomWords` itself (confirmed by reading `SubscriptionAPI.sol`/`VRFCoordinatorV2_5Mock.sol` directly, not assumed). Consequence: `performUpkeep` can succeed and lock the round into `CALCULATING` even with an empty subscription, and if it then runs dry (or was already dry) by the time Chainlink attempts fulfillment, that fulfillment reverts — **and the round has no way to recover**, since `performUpkeep` refuses to run again while `CALCULATING`, and `fulfillRandomWords` can only ever be invoked by the coordinator. Test `test_draw_getsStuckInCalculating_ifSubscriptionRunsDryBeforeFulfillment` proves this exact stuck state. Whether the *real* (non-mock) VRFCoordinatorV2_5 also defers the balance check to fulfillment time wasn't independently confirmed — flagged here rather than assumed either way. **This is a known, accepted operational risk, not a code bug**: the mitigation is keeping the subscription funded with headroom (matching ATTACK.md's own suggested framing), not new contract logic — adding an on-chain balance pre-check would mean querying the coordinator's `getSubscription()` before every request, which is exactly the kind of defensive complexity CLAUDE.md asks to avoid unless the user actually wants it. Not raised as a yes/no question yet since it wasn't part of the original two the user answered — worth a decision if the user wants a guard added.
5. **Reentrancy through `buyTicket`'s refund (ATTACK.md #15)** — CEI already made this safe by construction (same reasoning as `claimPrize`'s Step 7 test), but there was no dedicated proof for `buyTicket` specifically. `ReentrantBuyer.receive()` re-enters `buyTicket` with the refunded ETH; proven to just register as a second legitimate purchase (2 entries, pool = 2× price), not an exploit.

**Test-writing bug hit a third time**: `vm.deal(actor, amount)` then calling `actor.someFunction{value: amount}(...)` *from the test contract* sends `amount` from the *test contract's* balance, not the dealt actor's — the deal just sits unused and corrupts later balance assertions. This is the exact same mistake from Step 3 (`RejectingReceiver`) and Step 6 (`RejectingReceiver` again), now also hit in `ReentrantBuyer`. The rule going forward: only deal ETH to whichever address is *actually the `msg.sender` of the value-carrying call* — if the test contract itself calls `actor.buy{value: x}(...)`, the test contract needs the balance (usually already has enough by default), not the actor.
