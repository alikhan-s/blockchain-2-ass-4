// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console2} from "forge-std/Test.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {ParameterRegistry} from "../src/ParameterRegistry.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @dev Shared deployment for the entire DAO stack:
///      Token -> Vesting -> Timelock(2-day) -> Governor -> wire roles -> distribute votes.
abstract contract DAOFixture is Test {
    //    CONSTANTS

    uint256 internal constant TOTAL_SUPPLY = 100_000_000 ether;
    uint256 internal constant ALICE_VOTES = 5_000_000 ether; // > quorum (4M) alone
    uint256 internal constant BOB_VOTES = 3_000_000 ether; // < quorum alone
    uint256 internal constant CHARLIE_VOTES = 1_500_000 ether;
    uint256 internal constant SMALL_HOLDER_VOTES = 500_000 ether; // < proposal threshold (1M)

    uint256 internal constant TIMELOCK_DELAY = 2 days;

    //    ACTORS

    address internal deployer = makeAddr("deployer");
    address internal treasuryEoa = makeAddr("treasuryEoa"); // initial token treasury (pre-DAO)
    address internal airdrop = makeAddr("airdrop");
    address internal liquidity = makeAddr("liquidity");

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal charlie = makeAddr("charlie");
    address internal smallHolder = makeAddr("smallHolder");

    //    CONTRACTS

    GovernanceToken internal token;
    TokenVesting internal vesting;
    TimelockController internal timelock;
    MyGovernor internal governor;
    ParameterRegistry internal registry;

    function setUp() public virtual {
        vm.startPrank(deployer);

        //    Token + Vesting (CREATE-address prediction)
        uint64 startNonce = vm.getNonce(deployer);
        address predictedToken = vm.computeCreateAddress(deployer, startNonce + 1);
        vesting = new TokenVesting(predictedToken, deployer);
        token = new GovernanceToken(address(vesting), treasuryEoa, airdrop, liquidity);
        require(address(token) == predictedToken, "create-address mismatch");

        //    TimelockController -- admin role temporarily granted to deployer
        //    so we can wire Governor roles, then revoked.
        address[] memory proposers; // empty (will grant to Governor below)
        address[] memory executors; // empty
        timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, deployer);

        //    Governor
        governor = new MyGovernor(IVotes(address(token)), timelock);

        //    Roles: Governor is the sole PROPOSER & sole EXECUTOR.
        //    Then revoke admin role from deployer (DAO becomes self-sovereign).
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopPrank();

        //    Auxiliary: ParameterRegistry whose owner is the Timelock,
        //    so only DAO-executed proposals can change `value`.
        registry = new ParameterRegistry(address(timelock), 1);

        //    Distribute voting tokens from treasury EOA to test voters
        //    (in production, the treasury would itself be the Timelock).
        vm.startPrank(treasuryEoa);
        token.transfer(alice, ALICE_VOTES);
        token.transfer(bob, BOB_VOTES);
        token.transfer(charlie, CHARLIE_VOTES);
        token.transfer(smallHolder, SMALL_HOLDER_VOTES);
        // Move the rest of treasury's holdings to the Timelock so the DAO controls them.
        token.transfer(address(timelock), token.balanceOf(treasuryEoa));
        vm.stopPrank();

        // Self-delegate so checkpoints are activated.
        _selfDelegate(alice);
        _selfDelegate(bob);
        _selfDelegate(charlie);
        _selfDelegate(smallHolder);

        // Advance one block so getPastVotes(account, snapshot) sees the delegation.
        vm.roll(block.number + 1);
    }

    function _selfDelegate(address who) internal {
        vm.prank(who);
        token.delegate(who);
    }

    //    PROPOSAL HELPERS

    /// @dev Build a single-action proposal (token.transfer from Timelock).
    function _buildTransferProposal(address recipient, uint256 amount, string memory description)
        internal
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc,
            bytes32 descHash
        )
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(token.transfer, (recipient, amount));
        desc = description;
        descHash = keccak256(bytes(description));
    }

    /// @dev Pretty-print a proposal state for the lifecycle "report".
    function _stateLabel(IGovernor.ProposalState s) internal pure returns (string memory) {
        if (s == IGovernor.ProposalState.Pending) return "Pending";
        if (s == IGovernor.ProposalState.Active) return "Active";
        if (s == IGovernor.ProposalState.Canceled) return "Canceled";
        if (s == IGovernor.ProposalState.Defeated) return "Defeated";
        if (s == IGovernor.ProposalState.Succeeded) return "Succeeded";
        if (s == IGovernor.ProposalState.Queued) return "Queued";
        if (s == IGovernor.ProposalState.Expired) return "Expired";
        if (s == IGovernor.ProposalState.Executed) return "Executed";
        return "Unknown";
    }
}

//    ROLES & WIRING

contract GovernorWiringTest is DAOFixture {
    function test_GovernorParametersAreCorrect() public {
        assertEq(governor.votingDelay(), 7_200, "voting delay = 1 day in blocks");
        assertEq(governor.votingPeriod(), 50_400, "voting period = 1 week in blocks");
        assertEq(governor.proposalThreshold(), 1_000_000 ether, "proposal threshold = 1% supply");
        assertEq(governor.quorumNumerator(), 4, "quorum numerator = 4");
        // Quorum at the previous block: 4% of total supply.
        uint256 q = governor.quorum(block.number - 1);
        assertEq(q, (TOTAL_SUPPLY * 4) / 100, "quorum amount = 4M GOV");
    }

    function test_TimelockRolesAreOnlyGovernor() public {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), "governor proposer");
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(governor)), "governor executor");
        assertTrue(timelock.hasRole(timelock.CANCELLER_ROLE(), address(governor)), "governor canceller");
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer), "deployer admin revoked");
        assertFalse(timelock.hasRole(timelock.PROPOSER_ROLE(), deployer), "deployer not proposer");
        assertEq(timelock.getMinDelay(), 2 days, "timelock delay = 2 days");
    }
}

//    2. FULL LIFECYCLE (token transfer)

contract GovernorLifecycleTest is DAOFixture {
    /// @notice End-to-end happy path with verbose logging suitable for a report.
    /// Proposes a transfer of 100_000 GOV from the Timelock (treasury) to a grant recipient.
    function test_FullLifecycle_TimelockTransfersTokens() public {
        address grantRecipient = makeAddr("grantRecipient");
        uint256 grantAmount = 100_000 ether;

        console2.log("================================================================");
        console2.log(" DAO GOVERNANCE -- FULL LIFECYCLE EXECUTION LOG");
        console2.log("================================================================");
        console2.log("[setup] Total supply:           %s GOV", TOTAL_SUPPLY / 1 ether);
        console2.log("[setup] Quorum threshold:       %s GOV", governor.quorum(block.number - 1) / 1 ether);
        console2.log("[setup] Proposal threshold:     %s GOV", governor.proposalThreshold() / 1 ether);
        console2.log("[setup] Voting delay  (blocks): %s", governor.votingDelay());
        console2.log("[setup] Voting period (blocks): %s", governor.votingPeriod());
        console2.log("[setup] Timelock delay (sec):   %s", timelock.getMinDelay());
        console2.log("");

        // STEP 1 -- Build proposal payload
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc,
            bytes32 descHash
        ) = _buildTransferProposal(grantRecipient, grantAmount, "Proposal #1: Grant 100k GOV to research team");

        console2.log("[step 1] Proposer = alice (5M voting power)");
        console2.log("[step 1] Action: token.transfer(grantRecipient, 100_000 ether)");

        // STEP 2 -- Propose
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);
        console2.log("[step 2] Proposal created. id =", proposalId);
        console2.log("[step 2] State -> %s", _stateLabel(governor.state(proposalId)));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // STEP 3 -- Roll past voting delay (proposal becomes Active)
        vm.roll(block.number + governor.votingDelay() + 1);
        console2.log("[step 3] Rolled forward votingDelay+1 blocks. block.number =", block.number);
        console2.log("[step 3] State -> %s", _stateLabel(governor.state(proposalId)));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active));

        // STEP 4 -- Cast votes (alice + bob vote For, charlie Abstain)
        vm.prank(alice);
        governor.castVote(proposalId, 1); // For
        console2.log("[step 4] alice voted For   (5_000_000 GOV)");

        vm.prank(bob);
        governor.castVote(proposalId, 1); // For
        console2.log("[step 4] bob   voted For   (3_000_000 GOV)");

        vm.prank(charlie);
        governor.castVote(proposalId, 2); // Abstain
        console2.log("[step 4] charlie voted Abstain (1_500_000 GOV)");

        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);
        console2.log("[step 4] Tally: For=%s Against=%s Abstain=%s", forVotes / 1 ether, against, abstain / 1 ether);

        // STEP 5 -- Roll past voting period (proposal Succeeded)
        vm.roll(block.number + governor.votingPeriod() + 1);
        console2.log("[step 5] Rolled forward votingPeriod+1 blocks. block.number =", block.number);
        console2.log("[step 5] State -> %s", _stateLabel(governor.state(proposalId)));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // STEP 6 -- Queue into Timelock
        governor.queue(targets, values, calldatas, descHash);
        console2.log("[step 6] Proposal queued in TimelockController.");
        console2.log("[step 6] State -> %s", _stateLabel(governor.state(proposalId)));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // STEP 7 -- Wait the 2-day timelock delay
        vm.warp(block.timestamp + 2 days + 1);
        console2.log("[step 7] Warped forward 2 days. block.timestamp =", block.timestamp);

        // STEP 8 -- Execute
        uint256 timelockBefore = token.balanceOf(address(timelock));
        governor.execute(targets, values, calldatas, descHash);
        console2.log("[step 8] Proposal executed.");
        console2.log("[step 8] State -> %s", _stateLabel(governor.state(proposalId)));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));

        assertEq(token.balanceOf(grantRecipient), grantAmount, "recipient received grant");
        assertEq(token.balanceOf(address(timelock)), timelockBefore - grantAmount, "timelock debited");

        console2.log("[done ] grantRecipient balance: %s GOV", token.balanceOf(grantRecipient) / 1 ether);
        console2.log("================================================================");
    }
}

//    PROPOSAL CHANGING ANOTHER CONTRACT'S PARAMETERS

contract GovernorParameterChangeTest is DAOFixture {
    function test_ProposalChangesRegistryValue() public {
        // Build proposal: registry.setValue(42)
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(registry);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(registry.setValue, (42));
        string memory desc = "Update registry.value -> 42";
        bytes32 descHash = keccak256(bytes(desc));

        assertEq(registry.value(), 1, "initial value");

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);
        governor.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + 2 days + 1);
        governor.execute(targets, values, calldatas, descHash);

        assertEq(registry.value(), 42, "value updated by DAO");
        console2.log("[param-change] registry.value() = %s (was 1)", registry.value());
    }

    function test_RevertWhen_NonTimelockCallsRegistry() public {
        vm.expectRevert();
        vm.prank(alice);
        registry.setValue(99);
    }

    /// @notice Governance can also rewire its own parameters via `setVotingDelay`,
    ///         which is gated by `onlyGovernance` (i.e., callable only by the timelock executor).
    function test_GovernanceCanReconfigureItself() public {
        uint48 newDelay = 14_400; // 2 days

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(governor.setVotingDelay, (newDelay));
        bytes32 descHash = keccak256(bytes("Increase voting delay to 2 days"));

        vm.prank(alice);
        governor.propose(targets, values, calldatas, "Increase voting delay to 2 days");

        vm.roll(block.number + governor.votingDelay() + 1);
        uint256 proposalId =
            governor.hashProposal(targets, values, calldatas, keccak256(bytes("Increase voting delay to 2 days")));
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);
        governor.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + 2 days + 1);
        governor.execute(targets, values, calldatas, descHash);

        assertEq(governor.votingDelay(), newDelay);
    }
}

//    FAILURE / REVERT SCENARIOS

contract GovernorFailureTest is DAOFixture {
    function test_DefeatedWhen_QuorumNotMet() public {
        // Only smallHolder (500k) and charlie (1.5M) vote: 2M < 4M quorum.
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc,
        ) = _buildTransferProposal(makeAddr("recipient"), 1 ether, "low-turnout proposal");

        vm.prank(alice); // alice has threshold to propose
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(charlie);
        governor.castVote(proposalId, 1);
        vm.prank(smallHolder);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));

        console2.log("[quorum-fail] Final state: %s (votes 2M < quorum 4M)", _stateLabel(governor.state(proposalId)));
    }

    function test_DefeatedWhen_MajorityAgainst() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc,
        ) = _buildTransferProposal(makeAddr("recipient"), 1 ether, "controversial proposal");

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + governor.votingDelay() + 1);
        // 5M For (alice) vs 4.5M Against (bob 3M + charlie 1.5M) -- quorum hit either way.
        // Flip it so Against wins:
        vm.prank(alice);
        governor.castVote(proposalId, 0); // alice votes Against (5M)
        vm.prank(bob);
        governor.castVote(proposalId, 1); // bob votes For (3M)
        vm.prank(charlie);
        governor.castVote(proposalId, 1); // charlie votes For (1.5M)

        // For=4.5M, Against=5M -> Defeated.
        vm.roll(block.number + governor.votingPeriod() + 1);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));

        (uint256 against, uint256 forVotes,) = governor.proposalVotes(proposalId);
        console2.log("[majority-against] For=%s Against=%s -> Defeated", forVotes / 1 ether, against / 1 ether);
    }

    function test_RevertWhen_BelowProposalThreshold() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory desc,) =
            _buildTransferProposal(makeAddr("recipient"), 1 ether, "tiny holder propose");

        vm.prank(smallHolder); // 500k < 1M threshold
        vm.expectRevert();
        governor.propose(targets, values, calldatas, desc);
    }

    function test_RevertWhen_VotingTwice() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc,
        ) = _buildTransferProposal(makeAddr("recipient"), 1 ether, "double-vote proposal");

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.prank(alice);
        vm.expectRevert();
        governor.castVote(proposalId, 1);
    }

    function test_RevertWhen_QueueBeforeVotingEnds() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc,
            bytes32 descHash
        ) = _buildTransferProposal(makeAddr("recipient"), 1 ether, "queue-too-early proposal");

        vm.prank(alice);
        governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + governor.votingDelay() + 1);
        // Voting is Active, queue should revert.
        vm.expectRevert();
        governor.queue(targets, values, calldatas, descHash);
    }

    function test_RevertWhen_ExecuteBeforeTimelockDelay() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc,
            bytes32 descHash
        ) = _buildTransferProposal(makeAddr("recipient"), 1 ether, "execute-too-early proposal");

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);
        governor.queue(targets, values, calldatas, descHash);

        // Don't warp: timelock 2-day window has not elapsed.
        vm.expectRevert();
        governor.execute(targets, values, calldatas, descHash);
    }
}

//    5. DELEGATION TESTS

contract GovernorDelegationTest is DAOFixture {
    function test_DelegateVotesOnBehalfOfDelegator() public {
        // alice re-delegates her voting power to a fresh delegate.
        address delegatee = makeAddr("delegatee");

        vm.prank(alice);
        token.delegate(delegatee);

        // Need an extra block so the delegation is reflected in past checkpoints.
        vm.roll(block.number + 1);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc,
        ) = _buildTransferProposal(makeAddr("recipient"), 1 ether, "delegation proposal");

        // bob proposes (alice no longer holds voting power for threshold check).
        vm.prank(bob);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);

        vm.roll(block.number + governor.votingDelay() + 1);

        // Delegatee casts the vote, but the weight comes from alice's tokens (5M).
        vm.prank(delegatee);
        governor.castVote(proposalId, 1);

        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertEq(forVotes, ALICE_VOTES, "delegate's vote weight = delegator's balance");

        console2.log("[delegation] delegate cast vote with %s GOV (alice's tokens)", forVotes / 1 ether);
    }

    function test_VoteBySignatureRelayed() public {
        // alice will sign a vote off-chain; a relayer submits it on-chain (gasless).
        (address aliceEoa, uint256 alicePk) = makeAddrAndKey("aliceEoa");
        // Move 5M GOV to alice EOA and self-delegate.
        vm.prank(alice);
        token.transfer(aliceEoa, ALICE_VOTES);
        vm.prank(aliceEoa);
        token.delegate(aliceEoa);
        vm.roll(block.number + 1);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc,
        ) = _buildTransferProposal(makeAddr("recipient"), 1 ether, "vote-by-sig proposal");

        vm.prank(bob);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);
        vm.roll(block.number + governor.votingDelay() + 1);

        // EIP-712 ballot digest.
        bytes32 BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");
        uint256 nonce = governor.nonces(aliceEoa);
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, uint8(1), aliceEoa, nonce));
        bytes32 digest = _eip712Digest(structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        governor.castVoteBySig(proposalId, 1, aliceEoa, sig);

        (, uint256 forVotes,) = governor.proposalVotes(proposalId);
        assertEq(forVotes, ALICE_VOTES, "vote-by-sig counted with delegator's weight");
    }

    function test_VoteWithReasonEmitsReason() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory desc,
        ) = _buildTransferProposal(makeAddr("recipient"), 1 ether, "vote-with-reason proposal");

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);
        vm.roll(block.number + governor.votingDelay() + 1);

        vm.prank(alice);
        uint256 weight = governor.castVoteWithReason(proposalId, 1, "I support this initiative.");
        assertEq(weight, ALICE_VOTES);
    }

    function _eip712Digest(bytes32 structHash) internal view returns (bytes32) {
        // Re-derive EIP-712 domain separator from the Governor.
        bytes32 domainSeparator = _governorDomainSeparator();
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _governorDomainSeparator() internal view returns (bytes32) {
        // EIP-712: name="MyGovernor", version="1", chainId, verifyingContract=governor.
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("MyGovernor")),
                keccak256(bytes("1")),
                block.chainid,
                address(governor)
            )
        );
    }
}
