# CLAUDE.md

Guidelines for working in this Foundry/Solidity project. Part 1 covers how to think and behave while coding. Part 2 covers the technical conventions and workflow specific to this stack. Merge with any additional project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. In smart contracts that bias is *stronger than usual* — deployed code is often immutable and bugs can mean real, unrecoverable loss of funds. For trivial tasks (scripts, test helpers, local tooling), use judgment.

---

## Part 1 — Behavioral Guidelines

### 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask — especially about trust assumptions (who can call this? what if the oracle lies? what if the token is malicious/rebasing/fee-on-transfer?).
- If multiple interpretations exist, present them — don't pick silently. This applies doubly to anything touching access control, token accounting, or upgrade paths.
- If a simpler approach exists, say so. Push back when warranted — including pushing back on unnecessary upgradeability, unnecessary admin powers, or unnecessary cross-chain complexity.
- If something is unclear, stop. Name what's confusing. Ask. Never guess on economic parameters (fees, ratios, thresholds) — a wrong guess here is a silent vulnerability, not just a bug.

### 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested — every extra admin-settable parameter is an extra attack surface and an extra audit line item.
- No error handling for impossible scenarios — but *do* handle scenarios that are merely improbable if a malicious actor could force them (reentrancy, flash loans, sandwich attacks are "improbable," not "impossible").
- No upgradeability, proxies, or pausability unless explicitly requested — these are the most commonly over-added "just in case" features and each one adds real risk.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior auditor flag this as unnecessary attack surface?" If yes, simplify.

### 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing contracts:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken — especially anything already audited. An unaudited refactor of audited code is a regression risk even if it's objectively cleaner.
- Match existing style (NatSpec conventions, custom errors vs. require strings, OZ vs. Solady), even if you'd do it differently.
- If you notice unrelated dead code or a pre-existing vulnerability, mention it — don't delete or "fix" it silently.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.
- **Never change storage layout on an upgradeable contract without flagging it explicitly.** Reordering, resizing, or inserting state variables can corrupt storage on the next upgrade — this is not a normal refactor risk, it's a fund-loss risk.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after, and gas snapshot doesn't regress unexpectedly"
- "Add function Y" → "Write unit tests, a fuzz test for numeric inputs, and check it against the security checklist in Part 2"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [forge test / forge coverage / specific check]
2. [Step] → verify: [...]
3. [Step] → verify: [...]
```

**Verification here means actually running the tool, not describing what it would show.** Never report a test count, coverage percentage, or gas number without having run `forge test` / `forge coverage` / `forge snapshot` yourself in this session.

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification — and in a financial context, "make it work" without a security pass is not actually done.

### 5. Security Is Part of "Done"

A contract that compiles and passes the happy-path test is not finished. See the full security checklist in Part 2 before calling anything done. If you can't verify a check because a tool isn't installed (e.g. Slither), say so — don't silently skip it and imply the check passed.

---

## Part 2 — Foundry/Solidity Technical Reference

You are working in a **Foundry** codebase. Write secure, gas-efficient Solidity and validate every change with tests before considering it done. Never claim a task is finished without running `forge build` and `forge test` yourself.

### Project conventions

- Solidity version: pin to the version in `foundry.toml` / `pragma` — do not silently upgrade it.
- Style: NatSpec on all public/external functions, explicit visibility, custom errors instead of `require` strings (unless the codebase already uses require strings — match existing style).
- Libraries: prefer OpenZeppelin or Solady, whichever the repo already imports. Don't mix both for the same primitive (e.g. don't add Solady's ERC20 next to an OZ ERC20 already in use).
- Storage: pack structs deliberately; comment on any non-obvious slot packing.

### Workflow

1. **Understand before writing** — read the existing contracts, interfaces, and tests before adding new code. Check `foundry.toml` for remappings, optimizer settings, and solc version.
2. **Write the contract** — implement with checks-effects-interactions, explicit access control (Ownable/AccessControl — match repo convention), and events on every state-changing function.
3. **Write tests first or alongside** — unit tests for happy path + reverts, then fuzz tests (`forge test --fuzz-runs`) for functions with numeric/user-controlled inputs, then invariant tests for protocol-level properties (balances, supply, solvency) where relevant.
4. **Run and verify**:
   ```bash
   forge build
   forge test -vvv
   forge coverage
   forge fmt --check
   ```
5. **Static analysis** — run Slither if available (`slither .`) and address findings or explain why a finding is a false positive.
6. **Gas check** — `forge snapshot` before/after changes on gas-sensitive functions; report the delta.
7. **Never mark work done without actually running the above.** If a tool isn't installed, say so instead of assuming results.

### Security checklist (apply to every contract touched)

- [ ] Reentrancy: state updated before external calls, or `nonReentrant` used
- [ ] Access control on every privileged function
- [ ] No unchecked arithmetic without an explicit, commented reason
- [ ] External calls validated (return values checked, no unbounded loops over user-controlled arrays)
- [ ] If price/oracle data is used, verify the source is manipulation-resistant and appropriate for the protocol (e.g. Chainlink/TWAP rather than an exploitable spot AMM price).
- [ ] Upgradeable contracts: storage gaps present, `_authorizeUpgrade` restricted, initializer guarded against re-init
- [ ] Emergency pause / circuit breaker where the protocol handles user funds

### Testing stack

- **Foundry**: `forge test`, `forge coverage`, `forge snapshot`, fork tests via `--fork-url`
- Fuzzing: bound inputs with `vm.assume` or `bound()`, not raw rejection loops
- Invariant tests: define handlers in `test/invariant/`, keep ghost variables minimal
- Fork testing: pin block number for reproducibility (`--fork-block-number`)

### Deployment scripting

- Use `forge script` with `vm.startBroadcast()` / `vm.stopBroadcast()`, never hardcode private keys — read from `--private-key`, `--ledger`, or env var reference.
- Deterministic deployment via `CREATE2` where cross-chain address parity matters.
- Verify on the block explorer as part of the deploy script (`--verify`) when an API key is configured.

### Gas optimization (apply only where profiling shows it matters — don't micro-optimize blindly)

- Pack storage variables into fewer slots
- Use `calldata` over `memory` for external function args
- Cache storage reads used more than once in a function into a local variable
- Prefer `immutable`/`constant` for values fixed at deploy time
- Batch operations where users would otherwise pay repeated base costs

### When reporting progress

Report only what you actually ran and observed — real test counts, real coverage percentages, real gas deltas from `forge snapshot`. Never fabricate numbers to sound complete.

### Stack reference

- **Frameworks**: Foundry (forge, cast, anvil)
- **Libraries**: OpenZeppelin, Solady, Solmate
- **Indexing**: The Graph, Ponder, Envio
- **Frontend integration**: wagmi, viem, ethers.js
- **Target chains**: Ethereum, Base, Arbitrum, Optimism, Polygon

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, clarifying questions come before implementation rather than after mistakes, and no reported test/coverage/gas numbers turn out to be unverified.