# Post-Deployment Verification & Monitoring Plan

This document is the operational runbook to use **immediately after** running `script/DeployDAO.s.sol` against a public network. It has two parts:

1. A blocking checklist that must pass before any token holders are pointed at the contracts.
2. A monitoring plan covering on-chain events, indexers (The Graph), and alerting (Tenderly / OpenZeppelin Defender).

---

## 1. Etherscan / Block-explorer verification checklist

> 💡 Run these checks on **every** deployed network (mainnet, testnet, L2). The contracts use the same source — bytecode mismatch = redeploy.

### 1.1 Source-code verification

```bash
# Verify each contract using foundry's built-in flag during the deploy:
forge script script/DeployDAO.s.sol:DeployDAO \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  -vvvv

# Or after-the-fact, per contract:
forge verify-contract <ADDRESS> src/GovernanceToken.sol:GovernanceToken \
  --chain-id 1 --watch \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address)" \
    $VESTING $TREASURY_EOA $AIRDROP $LIQUIDITY)
```

**Verify these on Etherscan:**

| # | Check | Expected |
| --- | --- | --- |
| 1.1.1 | Compiler version | `v0.8.27` |
| 1.1.2 | Optimization | `Yes`, runs = `200`, viaIR `true` |
| 1.1.3 | Source code matches the audited tag (e.g. `v1.0.0`) | Diff against the GitHub release. |
| 1.1.4 | "Contract" tab shows green check on each: `GovernanceToken`, `TokenVesting`, `TimelockController`, `MyGovernor`, `Treasury`, `Box` | All verified. |
| 1.1.5 | `MyGovernor` and `TimelockController` "Read as Proxy" tabs are absent | Contracts are non-upgradeable by design. |

### 1.2 Token contract sanity (`GovernanceToken`)

Use Etherscan's **Read Contract** tab:

| Method | Expected |
| --- | --- |
| `name()` | `"Governance Token"` |
| `symbol()` | `"GOV"` |
| `decimals()` | `18` |
| `totalSupply()` | `100000000000000000000000000` (= 100 M × 1e18) |
| `balanceOf(<vesting>)` | `40000000 * 1e18` |
| `balanceOf(<treasuryEoa>)` | `30000000 * 1e18` |
| `balanceOf(<airdrop>)` | `20000000 * 1e18` |
| `balanceOf(<liquidity>)` | `10000000 * 1e18` |
| `CLOCK_MODE()` | `"mode=blocknumber&from=default"` |
| `clock()` | current `block.number` (within ±1) |

### 1.3 Governor configuration

| Method | Expected |
| --- | --- |
| `name()` | `"MyGovernor"` |
| `votingDelay()` | `7200` |
| `votingPeriod()` | `50400` |
| `proposalThreshold()` | `1000000 * 1e18` |
| `quorumNumerator()` | `4` |
| `quorumDenominator()` | `100` |
| `quorum(<recent block>)` | `4000000 * 1e18` |
| `timelock()` | address of the deployed `TimelockController` |
| `token()` | address of the deployed `GovernanceToken` |
| `COUNTING_MODE()` | `"support=bravo&quorum=for,abstain"` |

### 1.4 Timelock roles (`TimelockController`)

Check via the Etherscan **Read Contract** → `hasRole`:

```
PROPOSER_ROLE  = 0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1
EXECUTOR_ROLE  = 0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63
CANCELLER_ROLE = 0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783
DEFAULT_ADMIN_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000000
```

| Query | Expected |
| --- | --- |
| `hasRole(PROPOSER_ROLE, <governor>)` | `true` |
| `hasRole(CANCELLER_ROLE, <governor>)` | `true` |
| `hasRole(EXECUTOR_ROLE, address(0))` *(if `OPEN_EXECUTOR=true`)* | `true` |
| `hasRole(EXECUTOR_ROLE, <governor>)` *(if `OPEN_EXECUTOR=false`)* | `true` |
| `hasRole(DEFAULT_ADMIN_ROLE, <deployer>)` | **`false`** ← critical |
| `hasRole(DEFAULT_ADMIN_ROLE, <timelock>)` | `true` (timelock self-administers) |
| `getMinDelay()` | `172800` (2 days) |

> **Stop-the-line:** if `hasRole(DEFAULT_ADMIN_ROLE, <deployer>)` returns `true`, the deploy did **not** finalize correctly. Do not announce the contracts. Re-run `script/DeployDAO.s.sol` from a fresh deployer.

### 1.5 DAO-managed contracts (`Treasury`, `Box`)

| Method | Expected |
| --- | --- |
| `Treasury.timelock()` | address of `TimelockController` |
| `Treasury.ethBalance()` | `0` (or the seed amount, if pre-funded) |
| `Box.timelock()` | address of `TimelockController` |
| `Box.retrieve()` | `0` |

### 1.6 Smoke-test transactions (testnet)

Before mainnet, run on testnet:

1. `delegate(self)` from a holder address → verify `getVotes` updates.
2. Submit a tiny proposal (`Box.store(1)`) → walk it through the full lifecycle.
3. Confirm `ProposalCreated`, `VoteCast`, `ProposalQueued`, `ProposalExecuted`, and `ValueChanged(0,1)` events appear on Etherscan in order.

### 1.7 Deployer key hygiene

| Action | Notes |
| --- | --- |
| Move ETH leftover from deployer EOA to a cold wallet | Reduces blast radius if the key leaks later. |
| Rotate the deployer key out of any hot CI runner | The key has no on-chain power, but it can still spoof unverified contracts. |
| Archive `broadcast/DeployDAO.s.sol/<chainId>/run-latest.json` to long-term storage | Source of truth for "what was deployed at what nonce". |

---

## 2. Monitoring & alerting plan

The monitoring story has three layers:

```
On-chain events -> Indexer (The Graph subgraph) -> Public dashboards / docs
                -> Real-time alerting (Tenderly / Defender / OpenZeppelin Sentinel)
                -> Anomaly detection (multi-event rules, off-chain ML if budget allows)
```

### 2.1 Critical events to index

| Source | Event | Why it matters |
| --- | --- | --- |
| `MyGovernor` | `ProposalCreated(uint256 proposalId, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 voteStart, uint256 voteEnd, string description)` | Every governance action originates here. Decode `targets/calldatas` for human-readable summaries. |
| `MyGovernor` | `VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason)` | Real-time tally; vote-buying or whale alerts. |
| `MyGovernor` | `ProposalQueued(uint256 proposalId, uint256 etaSeconds)` | 2-day countdown until execution — deadline for any defensive `cancel()` proposal. |
| `MyGovernor` | `ProposalExecuted(uint256 proposalId)` / `ProposalCanceled` | Lifecycle terminal states. |
| `TimelockController` | `CallScheduled(bytes32 id, uint256 index, address target, uint256 value, bytes data, bytes32 predecessor, uint256 delay)` | Cross-check against `ProposalQueued`; mismatch = corruption. |
| `TimelockController` | `CallExecuted(bytes32 id, uint256 index, address target, uint256 value, bytes data)` | Confirms what *actually* ran on-chain. |
| `TimelockController` | `RoleGranted` / `RoleRevoked` / `MinDelayChange` | Should be **silent** post-deploy. Any emission is a P0 alert. |
| `GovernanceToken` | `DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate)` | Concentration tracking — alert if any single delegate crosses 5% / 10% / 20% / 33% / 50% of the supply. |
| `GovernanceToken` | `DelegateVotesChanged(address indexed delegate, uint256 previousVotes, uint256 newVotes)` | Real-time voting-power leaderboard. |
| `GovernanceToken` | `Transfer(address indexed from, address indexed to, uint256 value)` | Token-flow heat-map; OTC desk movements. |
| `TokenVesting` | `ScheduleCreated(address indexed beneficiary, uint256 amount, uint64 start, uint64 duration)` | Audit trail for team allocations. |
| `TokenVesting` | `TokensReleased(address indexed beneficiary, uint256 amount)` | Insider unlock tracker — pair with DEX liquidity to flag sells. |
| `Treasury` | `ETHReceived` / `ETHWithdrawn` / `ERC20Withdrawn` / `ArbitraryCall` | Financial accounting + anomaly base. |
| `Box` (and any future managed contract) | `ValueChanged(uint256 oldValue, uint256 newValue)` | Confirms execution of parameter-update proposals. |

### 2.2 The Graph — minimal subgraph schema

```graphql
type Proposal @entity {
  id: ID! # proposalId as decimal string
  proposer: Bytes!
  description: String!
  voteStart: BigInt!
  voteEnd: BigInt!
  state: String!  # Pending | Active | Canceled | Defeated | Succeeded | Queued | Expired | Executed
  forVotes: BigDecimal!
  againstVotes: BigDecimal!
  abstainVotes: BigDecimal!
  votes: [Vote!]! @derivedFrom(field: "proposal")
  queuedAt: BigInt
  executedAt: BigInt
}

type Vote @entity {
  id: ID! # tx hash + log index
  proposal: Proposal!
  voter: Bytes!
  support: Int!  # 0=Against, 1=For, 2=Abstain
  weight: BigDecimal!
  reason: String!
  blockNumber: BigInt!
  timestamp: BigInt!
}

type Delegation @entity {
  id: ID! # delegator address
  delegator: Bytes!
  delegate: Bytes!
  votes: BigDecimal!
  updatedAt: BigInt!
}

type DelegateLeaderboard @entity {
  id: ID! # delegate address
  delegate: Bytes!
  votes: BigDecimal!
  shareOfSupply: BigDecimal! # 0.0 - 1.0
  updatedAt: BigInt!
}

type VestingRelease @entity {
  id: ID!
  beneficiary: Bytes!
  amount: BigDecimal!
  txHash: Bytes!
  timestamp: BigInt!
}

type TreasuryFlow @entity {
  id: ID!
  direction: String! # in | out
  asset: Bytes! # 0x0 for ETH, otherwise ERC-20 address
  counterparty: Bytes!
  amount: BigDecimal!
  txHash: Bytes!
  timestamp: BigInt!
}
```

Suggested mapping handlers:

| Event | Handler | Side-effects |
| --- | --- | --- |
| `ProposalCreated` | `handleProposalCreated` | Create `Proposal`. |
| `VoteCast` | `handleVoteCast` | Append `Vote`; update tally on `Proposal`. |
| `ProposalQueued/Executed/Canceled` | `handleProposalState` | Update `Proposal.state`. |
| `DelegateChanged` + `DelegateVotesChanged` | `handleDelegate*` | Upsert `Delegation` and `DelegateLeaderboard`. |
| `TokensReleased` | `handleVestingRelease` | Append `VestingRelease`. |
| `ETHReceived` / `ETHWithdrawn` / `ERC20Withdrawn` | `handleTreasuryFlow` | Append `TreasuryFlow`. |

The subgraph powers the public dashboard and acts as the source of truth for the frontend.

### 2.3 Tenderly / OpenZeppelin Defender Sentinel rules

**P0 — Immediate page (e.g. PagerDuty)**

| Rule | Trigger |
| --- | --- |
| Timelock role drift | `TimelockController.RoleGranted` or `RoleRevoked` after the deploy block. |
| Min delay change | `TimelockController.MinDelayChange` (governance only — but verify out-of-band). |
| Treasury arbitrary call | `Treasury.ArbitraryCall(target, value, data)` where `target` not in an allowlist (Box, Registry, future modules). |
| Whale concentration | `DelegateVotesChanged` such that `newVotes / totalSupply >= 33%`. |
| Deployer admin re-grant | `hasRole(DEFAULT_ADMIN_ROLE, <deployer>) == true` (poll once per block). |

**P1 — Slack/Telegram channel**

| Rule | Trigger |
| --- | --- |
| New proposal | `ProposalCreated`. Auto-post a Tenderly simulation link. |
| Vote landed | `VoteCast` with `weight >= 1% of totalSupply`. |
| Quorum reached | Compute `for + abstain >= quorum(snapshot)` and post once per proposal. |
| Proposal queued | `ProposalQueued` — start a 2-day countdown. |
| Proposal about to execute | T-2h before `etaSeconds`. |
| Proposal executed | `ProposalExecuted` + Tenderly trace + diff against the simulated trace. |
| Vesting unlock | `TokensReleased` ≥ 100 k GOV. |
| Treasury outflow | `Treasury.ETHWithdrawn` or `ERC20Withdrawn`. |

**P2 — Daily digest**

| Metric | Source |
| --- | --- |
| Active proposals + tallies | Subgraph |
| Delegate leaderboard top-25 | Subgraph |
| Vesting unlock schedule (next 7 / 30 days) | `TokenVesting.scheduleOf(...)` per beneficiary |
| Treasury balances (ETH + each ERC-20) | RPC reads against `Treasury.tokenBalance` |

### 2.4 Health-check job (cron, every 5 min)

A small off-chain worker that asserts the post-deploy invariants from §1 are still true. Failure pages on-call:

```python
ASSERT(timelock.hasRole(PROPOSER_ROLE, governor.address))
ASSERT(timelock.hasRole(EXECUTOR_ROLE, ZERO if OPEN_EXECUTOR else governor.address))
ASSERT(NOT timelock.hasRole(DEFAULT_ADMIN_ROLE, deployer.address))
ASSERT(timelock.getMinDelay() == 172800)
ASSERT(governor.votingDelay() == 7200)
ASSERT(governor.votingPeriod() == 50400)
ASSERT(governor.proposalThreshold() == 1_000_000 * 10**18)
ASSERT(governor.quorumNumerator() == 4)
ASSERT(token.totalSupply() == 100_000_000 * 10**18)
ASSERT(token.balanceOf(vesting.address) + sum(transfers_out) == 40_000_000 * 10**18)
```

Drift in any of these means the contracts have been mutated (or governance has *intentionally* mutated them — verify by replaying the proposal log against the subgraph).

### 2.5 Incident response runbook (one-pager)

1. **Page received** → check the Sentinel rule that fired.
2. **Triage** → open the linked tx on Tenderly. Re-simulate to confirm the on-chain effect.
3. **Containment** → if a malicious proposal is in the queue, draft a `Governor.cancel(...)` proposal (CANCELLER_ROLE = Governor) and start the voting period immediately. The 2-day Timelock window is the time budget.
4. **Coordination** → broadcast on the governance forum + Discord. Pin a Tenderly simulation showing the hostile payload.
5. **Post-mortem** → after resolution, file an audit appendix in this repo and add a regression test under `test/`.

---

## 3. Quick links template (paste into release notes)

```
==================
DAO release v1.0.0
==================
Network          : Sepolia Testnet
[1] TokenVesting    : 0xc0E4Ce3a6d66dfCe334b0De19784d8c91aFE0898
[2] GovernanceToken : 0x2D66D772ccF068cb54B28D14f8b7B6087DE48CB1
[3] TimelockController: 0x2787cAc10cfD49d76cAc6A2a36a5Ce230feb12C4
[4] MyGovernor      : 0x6027FD117b73e085c80Ac3E5d2a33110ecbBA757
    EXECUTOR_ROLE -> address(0) (open executor)
    DEFAULT_ADMIN_ROLE revoked from deployer
[5] Treasury        : 0x7Dd6d7Ed4541C18bF1dffa962373B969EA6D44E9
[6] Box             : 0x6C5487fB8849e888A778662A530C5d80C9F92d7f
SECURITY_AUDIT.md: ./SECURITY_AUDIT.md
```
