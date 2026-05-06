# Security Audit — MyGovernor DAO

**Scope.** `GovernanceToken.sol`, `TokenVesting.sol`, `MyGovernor.sol`, `Treasury.sol`, `Box.sol`, `ParameterRegistry.sol`, `TimelockController` (OpenZeppelin v5.1.0, used as-is), and the Foundry deployment script `script/DeployDAO.s.sol`.

**Methodology.**
- Static analysis with Slither (expected findings annotated below).
- Manual review against the OWASP Smart Contract Top 10 and OpenZeppelin's *Governor* security guidance.
- 46 Foundry tests covering role wiring, lifecycle, timing, delegation, signature replay, and trust-boundary violations.
- Threat modelling for centralization (whale takeover) and Flash-Loan governance attacks.

---

## 1. Severity legend

| Level | Meaning |
| --- | --- |
| **Critical** | Direct loss of user funds or DAO control. |
| **High** | Plausible attack path under specific (but realistic) preconditions. |
| **Medium** | Defence-in-depth weakness; not exploitable in isolation. |
| **Low** | Hardening opportunity / informational. |
| **Note** | Slither false-positive or by-design behaviour. |

---

## 2. Static analysis — expected Slither output

Running `slither . --solc-remaps "@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/ forge-std/=lib/forge-std/src/" --filter-paths "lib/"` will surface the following classes of findings. Each is documented with the rationale and accept/fix decision.

### 2.1 `timestamp` — use of `block.timestamp` *(Note)*

**Where.**
- `TokenVesting._vestedAmount` compares `block.timestamp` against the schedule's start.
- `TimelockController` (OZ) and `MyGovernor.proposalEta` use timestamps for the queue delay.

**Risk.** Miner/validator timestamp drift is bounded to ±15 seconds on Ethereum mainnet (PoS) and is therefore irrelevant for windows measured in days (vesting → 365 d, queue delay → 2 d). For the Governor itself we explicitly use **block-number clock** (`ERC20Votes` default) for voting delay/period — those windows do not depend on `block.timestamp` at all.

**Decision.** Accept. Adding the typical mitigation (`uint64`-cast block.number) here would be net harmful: the Timelock is *meant* to use timestamps so its delay survives chain re-orgs and `block.number` skips on L2.

### 2.2 `reentrancy-events` — events emitted before external calls *(Note)*

**Where.** `TokenVesting.release`, `Treasury.withdrawETH/withdrawERC20/execute`.

**Risk.** None. The functions emit events first by design — combined with state writes happening *before* the external call, this is the canonical Checks-Effects-Interactions ordering. Slither's check is conservative.

**Decision.** Accept. The functions are also `nonReentrant`-guarded.

### 2.3 `unchecked-transfer` — return value of ERC-20 `transfer` *(Resolved)*

**Where.** Every external token movement uses `SafeERC20.safeTransfer` / `safeTransferFrom`, which reverts on `false` returns and on non-standard tokens. The only direct `transfer` call is in `GovernanceToken._update` (governance token itself) where the return value is enforced by OZ's ERC-20 implementation.

**Decision.** Resolved.

### 2.4 `naming-convention` — uppercase function `CLOCK_MODE` *(Note, was applicable in Part 1)*

`CLOCK_MODE()` follows EIP-6372 and **must** be uppercase. The override has been removed in this codebase (the token now exposes the OZ-default block-number clock), so the warning no longer applies.

### 2.5 `solc-version` *(Note)*

Pinned at `0.8.27`. This version is post-Cancun, includes transient storage support, and has no known critical bugs. We pin (`pragma solidity 0.8.27;`) rather than range-floating to make bytecode reproducible across re-deployments.

### 2.6 `low-level-calls` — `Treasury.execute` uses `target.call{value: value}(data)` *(Accepted)*

**Where.** `Treasury.execute(address target, uint256 value, bytes calldata data)`.

**Risk.** Low-level calls bypass type-checks and can hit `selfdestruct`-prone contracts. We accept this because:
1. The function is gated by `onlyTimelock`, so the only way to reach it is through a successful, queued, executed DAO proposal — i.e. token-holders have already approved the exact `(target, value, data)` triple.
2. Reverts are surfaced (`if (!ok) revert CallFailed();`) and the function is `nonReentrant`.
3. Without `execute` the Treasury would not be able to perform parameter updates / contract upgrades, which is the entire point of the contract.

### 2.7 `arbitrary-send-eth` — `Address.sendValue(to, amount)` *(Accepted)*

`Treasury.withdrawETH` forwards ETH to a DAO-approved recipient. The destination is determined by an executed proposal, so it is never *arbitrary* in the slither sense.

### 2.8 `assembly` *(N/A)*

No inline assembly used in our contracts. OZ libraries do, but they are out of audit scope.

---

## 3. Centralization risks

### 3.1 Whale-takeover ("majority attack")

**Threat model.** An adversary acquires `>50%` of `GOV` (e.g., on a DEX during a depegging event, or by colluding with large holders) and attempts to drain the Treasury via a malicious proposal.

**Defence-in-depth layers.**

| Layer | Mechanism | What it buys minority holders |
| --- | --- | --- |
| **Quorum (4%)** | Proposals require ≥4 M GOV worth of votes to be valid. *Not a whale defence on its own* — a whale exceeds quorum trivially. | Filters spam; baseline. |
| **Voting delay (1 day)** | A 7 200-block delay between `propose()` and the start of voting. | Token-holders see the proposal, can re-delegate, exit DEX positions, or coordinate counter-votes *before* the snapshot is taken. |
| **Voting period (1 week)** | 50 400 blocks of voting. | Time for off-chain debate, governance forums, and emergency social signalling (e.g., a `pause()` proposal). |
| **Timelock (2 days)** | Even if the malicious proposal passes, execution is delayed 2 days. | **The single most important minority-protection tool.** Honest holders can: (a) withdraw their LP positions; (b) stake/sell; (c) coordinate a counter-proposal to `cancel` (CANCELLER_ROLE on the Governor); (d) escape to a fork of the protocol. |
| **Treasury isolation** | DAO-controlled funds live in `Treasury.sol`, not in the Timelock itself. | Even a Governor-level bug (e.g., a vote-counting exploit) cannot drain custody without also matching the `onlyTimelock` modifier on `Treasury.withdraw*`. Limits blast radius. |
| **Vesting schedule** | 40% team allocation locked linearly for 12 months. | Prevents an "insider rug" via early team-token dump and ensures that voting power from the team is added gradually rather than instantaneously. |

**Residual risk.** A whale who is willing to wait 2 days *and* whose acquisition cost is justified by the Treasury TVL can still execute a hostile proposal. The protection is therefore not absolute — it is a **time-and-coordination buffer** for the minority. Production DAOs typically harden this further with:
- A multisig-controlled `Guardian` role with one-shot `cancel()` powers (we keep this *available* via `CANCELLER_ROLE` but assign it to the Governor itself; an explicit guardian is a recommended follow-up).
- Quorum/threshold ratchets (e.g. raise quorum to 10% if treasury > $X via a parametric proposal).
- A "veto" branch that lets long-term token-stakers reject proposals.

### 3.2 Governance over the token contract itself

`GovernanceToken` is **non-upgradeable** and has **no minter** beyond the constructor. Therefore even a 100% majority cannot inflate the supply or mint to a new address — the worst case is moving funds out of the Treasury. This is intentional: predictable supply is a hard property the DAO trades flexibility for.

### 3.3 Deployer key compromise

The deploy script (`script/DeployDAO.s.sol`) revokes `DEFAULT_ADMIN_ROLE` from the deployer at the end of the broadcast. After the script returns, the deployer key has **zero on-chain privileges**. The post-deploy invariant check enforces this:

```solidity
require(!dep.timelock.hasRole(dep.timelock.DEFAULT_ADMIN_ROLE(), deployer), "deployer still admin");
```

If verification on Etherscan ever shows the deployer holding the admin role, the deploy must be considered failed and the contracts re-deployed.

---

## 4. Flash-Loan governance attack — and why `getPastVotes` defeats it

### 4.1 Attack pattern (without snapshots)

A naive Governor that reads `balanceOf(account)` *at the moment of voting* is vulnerable to:

1. Attacker takes a flash-loan of `N` GOV tokens (more than the proposal threshold and quorum combined).
2. Within the same transaction:
   a. `delegate(self)` to activate voting power.
   b. `propose(maliciousAction)`.
   c. `castVote(proposalId, FOR)` — measured against current balance ⇒ counts the borrowed tokens.
   d. Fast-forward via griefing or, on a Governor without a delay, `execute()` immediately.
   e. Repay the flash-loan.

Net cost ≈ flash-loan fee (~0.09%). Net result ≈ DAO drained.

### 4.2 How `getPastVotes` neutralises it

`MyGovernor` inherits from `GovernorVotes`, which counts votes via:

```solidity
// from OZ v5 Votes.sol
function getPastVotes(address account, uint256 timepoint) public view returns (uint256) {
    uint48 currentTimepoint = clock();
    if (timepoint >= currentTimepoint) revert ERC5805FutureLookup(timepoint, currentTimepoint);
    return _checkpointsLookup(_delegateCheckpoints[account], timepoint);
}
```

The `timepoint` parameter passed by the Governor when tallying a vote is **`proposalSnapshot`** — set at proposal creation as `clock() + votingDelay`. By the time a voter calls `castVote`, the snapshot block is *strictly in the past*, and the checkpoint lookup is deterministic.

Putting it concretely against the flash-loan flow:

| Step | What the attacker does | What `getPastVotes` returns |
| --- | --- | --- |
| t=0 | Flash-borrows `N` GOV, calls `delegate(self)` — creates a checkpoint at block t=0. | n/a |
| t=0 | Calls `propose(...)` ⇒ `proposalSnapshot = t=0 + 7200`. | Future block — vote can't be cast yet. |
| t=0 | Tries `castVote` → reverts (`Governor: vote not currently active`). | n/a |
| t=0 | Repays flash-loan in the same transaction (must, or the loan reverts). Their delegate balance is decremented to 0 — checkpoint at t=0 records 0. | n/a |
| t=0 + 7200 | Voting opens; attacker tries to vote. | `getPastVotes(attacker, snapshot=7200)` returns **0** — the lookup pins to the *latest* checkpoint at-or-before the snapshot, which records the post-repayment balance. |

The atomicity of a flash-loan (one transaction = one block) is incompatible with the **mandatory `votingDelay > 0` block gap** between proposal creation and the start of voting. Voting power must persist across that gap, which a flash-loan cannot do without holding the tokens past the loan-repayment deadline — i.e., paying for them outright.

### 4.3 Configuration requirements for the protection to hold

The defence relies on three configured invariants. All three are asserted by the deploy script and the test suite:

1. **`votingDelay() > 0`.** We use `7 200` blocks. A zero delay would re-open the flash-loan window.
2. **`Governor.clock()` matches `Token.clock()`.** Both use `block.number` (asserted by `test_ClockModeIsBlockNumber`). Mismatched clocks would corrupt the snapshot lookup.
3. **No mid-proposal supply changes that bypass checkpoints.** `GovernanceToken` exposes no `mint` or `burn` to anyone after construction, so the only way to change `getPastVotes` is via `transfer` + `delegate`, which always create checkpoints.

### 4.4 Related, *non-defeated* attack: vote-buying

`getPastVotes` does not stop a wealthy actor from acquiring tokens, holding through the snapshot, and then dumping. The Timelock delay (§3.1) is the relevant defence there, not `getPastVotes`.

---

## 5. Per-contract findings

### 5.1 `GovernanceToken.sol`

- ✅ Constructor mints exactly `100_000_000 ether` total. Allocations sum to 10 000 BPS (no rounding remainder).
- ✅ `_update` calls `super._update` to keep `Votes` checkpoints consistent with balance changes.
- ✅ Custom error `DuplicateRecipient` prevents accidentally collapsing two roles into one address (which would shift the implicit voting weight).
- ⚠ **Note:** the four recipient addresses are `immutable`. If any of them needs to be rotated (e.g. compromised airdrop key), the only path is for the holder to `transfer` themselves. The contract has no admin override — by design.

### 5.2 `TokenVesting.sol`

- ✅ `release()` is `nonReentrant`. Even if the underlying token had a re-entrancy hook (e.g. ERC-777-style), the guard plus CEI ordering prevents double-claims.
- ✅ Schedule cannot be overwritten (`ScheduleAlreadyExists`).
- ✅ Outstanding-balance invariant prevents over-allocation.
- ⚠ **Low.** No revoke/clawback path for terminated employees. This is a product decision; in a corporate-style DAO consider adding a `revoke(address beneficiary)` callable by the timelock that zeroes the schedule and refunds the unvested portion.

### 5.3 `MyGovernor.sol`

- ✅ Composes the recommended OZ extension stack.
- ✅ All multi-inheritance overrides (`votingDelay`, `votingPeriod`, `proposalThreshold`, `quorum`, `state`, `proposalNeedsQueuing`, `_queueOperations`, `_executeOperations`, `_cancel`, `_executor`) are present and call `super` correctly.
- ✅ Block-number clock matches the token (asserted in tests).
- ⚠ **Medium.** No `GovernorPreventLateQuorum`. A whale could submit a swing vote in the last block of the voting period to prevent counter-mobilisation. **Recommendation:** add `GovernorPreventLateQuorum` with a 1-day extension before mainnet launch.

### 5.4 `Treasury.sol`

- ✅ Strict `onlyTimelock` gate. Custom error `NotTimelock(caller)` aids monitoring.
- ✅ `nonReentrant` on every external call.
- ✅ `receive()` emits `ETHReceived` for indexing.
- ⚠ **Low.** `execute` allows any `(target, value, data)` triple. Token-holders should review proposed payloads carefully. Consider adding an off-chain calldata-decoder (e.g. Tenderly-simulated trace) as a UX layer.

### 5.5 `Box.sol`

- ✅ Minimal surface; only `store(uint256)` is mutable, gated by `onlyTimelock`.
- ✅ `retrieve()` is view-only.

---

## 6. Test coverage summary

| Suite | Tests | Coverage |
| --- | --- | --- |
| `GovernanceTokenAllocationTest` | 4 | Constructor invariants, zero-address & duplicate-recipient reverts. |
| `GovernanceTokenVotesTest` | 7 | Delegation activation, `getPastVotes` snapshots, EIP-2612 permit + relayer, expired deadline, EIP-6372 clock. |
| `TokenVestingTest` | 11 | Vesting math at t=0/25%/50%/75%/100%/post-end, future-start schedule, all revert paths, vest→delegate flow. |
| `GovernorWiringTest` | 2 | Parameters, role wiring. |
| `GovernorLifecycleTest` | 1 | Full propose → vote → queue → execute path with verbose console log. |
| `GovernorParameterChangeTest` | 3 | DAO mutates registry, governance reconfigures itself. |
| `GovernorFailureTest` | 6 | Quorum-not-met, majority-against, threshold revert, double-vote, premature queue, premature execute. |
| `GovernorDelegationTest` | 3 | Delegate-on-behalf, `castVoteBySig`, `castVoteWithReason`. |
| `BoxE2ETest` | 3 | DAO → `Box.store(42)` happy path, non-timelock revert, multiple updates. |
| `TreasuryE2ETest` | 6 | ETH receive, ETH/ERC-20 withdrawal via DAO, trust-boundary check. |
| **Total** | **46** | All passing under `forge test`. |

Recommended additions before mainnet:
- Fuzz test on `_vestedAmount` (already deterministic but cheap to add).
- Invariant test on `Treasury` (`token.balanceOf(treasury) >= sum(unprocessedProposals.amount)`).
- Differential test against the deployed bytecode after Etherscan verification.

---

## 7. Recommendations summary (priority order)

| # | Severity | Recommendation |
| --- | --- | --- |
| 1 | High (operational) | Add a multisig-controlled `Guardian` with one-shot `cancel()` rights on the Timelock for incident response. |
| 2 | Medium | Inherit `GovernorPreventLateQuorum` to harden against late-vote whales. |
| 3 | Medium | Wire `Treasury` ↔ `Timelock` ETH-balance migration via a one-time bootstrap proposal so funds live in `Treasury`, not the Timelock. |
| 4 | Low | Add `revoke(address)` on `TokenVesting` for terminated team members. |
| 5 | Low | Run Slither + Mythril in CI; fail builds on new findings. |
| 6 | Low | Publish the `(targets, values, calldatas, descriptionHash)` of each proposal alongside a Tenderly simulation link in the governance forum. |
