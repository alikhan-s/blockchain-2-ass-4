// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";
import {TokenVesting} from "../src/TokenVesting.sol";

/// @dev Shared deployment helper: TokenVesting is deployed first using a
///      CREATE-address prediction for the GovernanceToken to satisfy the
///      circular dependency between the two contracts.
abstract contract DeployFixture is Test {
    GovernanceToken internal token;
    TokenVesting internal vesting;

    address internal owner = makeAddr("owner");
    address internal treasury = makeAddr("treasury");
    address internal airdrop = makeAddr("airdrop");
    address internal liquidity = makeAddr("liquidity");

    function setUp() public virtual {
        // Pre-compute the address of the GovernanceToken: it will be the
        // second contract this test contract deploys (nonce+1).
        uint64 startNonce = vm.getNonce(address(this));
        address predictedToken = vm.computeCreateAddress(address(this), startNonce + 1);

        vesting = new TokenVesting(predictedToken, owner);
        token = new GovernanceToken(address(vesting), treasury, airdrop, liquidity);

        assertEq(address(token), predictedToken, "predicted token address mismatch");
    }
}

contract GovernanceTokenAllocationTest is DeployFixture {
    function test_TotalSupplyMintedAtDeployment() public view {
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
        assertEq(token.TOTAL_SUPPLY(), 100_000_000 ether);
    }

    function test_AllocationsMatchTokenomics() public view {
        assertEq(token.balanceOf(address(vesting)), 40_000_000 ether, "team 40%");
        assertEq(token.balanceOf(treasury), 30_000_000 ether, "treasury 30%");
        assertEq(token.balanceOf(airdrop), 20_000_000 ether, "airdrop 20%");
        assertEq(token.balanceOf(liquidity), 10_000_000 ether, "liquidity 10%");
    }

    function test_RevertWhen_ConstructorReceivesZeroAddress() public {
        vm.expectRevert(GovernanceToken.ZeroAddress.selector);
        new GovernanceToken(address(0), treasury, airdrop, liquidity);
    }

    function test_RevertWhen_DuplicateRecipients() public {
        vm.expectRevert(GovernanceToken.DuplicateRecipient.selector);
        new GovernanceToken(treasury, treasury, airdrop, liquidity);
    }
}

contract GovernanceTokenVotesTest is DeployFixture {
    function test_DelegationActivatesVotingPower() public {
        // Treasury holds tokens but has no voting power until it delegates.
        assertEq(token.getVotes(treasury), 0, "no power before delegation");

        vm.prank(treasury);
        token.delegate(treasury);

        assertEq(token.getVotes(treasury), 30_000_000 ether, "self-delegated power");
    }

    function test_DelegationToThirdParty() public {
        address delegatee = makeAddr("delegatee");

        vm.prank(treasury);
        token.delegate(delegatee);

        assertEq(token.getVotes(treasury), 0);
        assertEq(token.getVotes(delegatee), 30_000_000 ether);
    }

    function test_VotingPowerSnapshotsViaGetPastVotes() public {
        vm.roll(100);

        // Self-delegate at block 100 (snapshotted under timepoint 100).
        vm.prank(treasury);
        token.delegate(treasury);

        // Move to block 101 and transfer half away (new checkpoint at 101).
        vm.roll(101);
        vm.prank(treasury);
        token.transfer(makeAddr("buyer"), 15_000_000 ether);

        // Move to block 102 so that 100 and 101 are strictly in the past.
        vm.roll(102);

        // Past votes at block 100: full 30M (transfer happened later).
        assertEq(token.getPastVotes(treasury, 100), 30_000_000 ether, "snapshot at b=100");
        // Past votes at block 101: 15M (after transfer at same block).
        assertEq(token.getPastVotes(treasury, 101), 15_000_000 ether, "snapshot at b=101");
    }

    function test_RevertWhen_QueryingFutureSnapshot() public {
        vm.expectRevert();
        token.getPastVotes(treasury, block.number + 1);
    }

    function test_PermitGivesApprovalViaSignature() public {
        // Create a fresh signing identity and seed it with tokens.
        (address ownerEoa, uint256 ownerPk) = makeAddrAndKey("ownerEoa");
        vm.prank(treasury);
        token.transfer(ownerEoa, 1_000 ether);

        address spender = makeAddr("spender");
        uint256 value = 500 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(ownerEoa);

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                ownerEoa,
                spender,
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        // Anyone can submit the permit. Gas is paid by the relayer.
        address relayer = makeAddr("relayer");
        vm.prank(relayer);
        token.permit(ownerEoa, spender, value, deadline, v, r, s);

        assertEq(token.allowance(ownerEoa, spender), value);
        assertEq(token.nonces(ownerEoa), nonce + 1);
    }

    function test_RevertWhen_PermitDeadlineExpired() public {
        (address ownerEoa, uint256 ownerPk) = makeAddrAndKey("ownerEoa");
        address spender = makeAddr("spender");

        uint256 deadline = block.timestamp;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                ownerEoa,
                spender,
                100,
                token.nonces(ownerEoa),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);

        vm.warp(deadline + 1);
        vm.expectRevert();
        token.permit(ownerEoa, spender, 100, deadline, v, r, s);
    }

    function test_ClockModeIsBlockNumber() public view {
        // Default OZ ERC20Votes clock is block.number — required so the Governor's
        // voting delay and voting period below can be expressed strictly in blocks.
        assertEq(token.CLOCK_MODE(), "mode=blocknumber&from=default");
        assertEq(uint256(token.clock()), block.number);
    }
}

contract TokenVestingTest is DeployFixture {
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant ALICE_AMOUNT = 1_000_000 ether;
    uint256 internal constant BOB_AMOUNT = 2_000_000 ether;

    uint64 internal startTs;

    function setUp() public override {
        super.setUp();
        startTs = uint64(block.timestamp);

        vm.startPrank(owner);
        vesting.createSchedule(alice, ALICE_AMOUNT, startTs);
        vesting.createSchedule(bob, BOB_AMOUNT, startTs);
        vm.stopPrank();
    }

    function test_NothingVestedAtStart() public {
        // Exactly at start, the proportional formula gives elapsed = 0 → vested = 0.
        // Calling release() must revert with NothingToRelease.
        vm.prank(alice);
        vm.expectRevert(TokenVesting.NothingToRelease.selector);
        vesting.release();
    }

    function test_LinearReleaseAtHalfway() public {
        vm.warp(startTs + (vesting.VESTING_DURATION() / 2));

        uint256 expected = ALICE_AMOUNT / 2;
        assertEq(vesting.releasable(alice), expected, "half-way releasable");

        vm.prank(alice);
        vesting.release();

        assertEq(token.balanceOf(alice), expected);
        assertEq(vesting.scheduleOf(alice).released, expected);
    }

    function test_FullReleaseAfterDuration() public {
        vm.warp(startTs + vesting.VESTING_DURATION());

        vm.prank(alice);
        vesting.release();
        vm.prank(bob);
        vesting.release();

        assertEq(token.balanceOf(alice), ALICE_AMOUNT, "alice fully vested");
        assertEq(token.balanceOf(bob), BOB_AMOUNT, "bob fully vested");
        assertEq(vesting.outstanding(), 0);
    }

    function test_VestingClampsAfterDurationEnds() public {
        // Warp far past the schedule's end - vested must clamp to totalAmount.
        vm.warp(startTs + vesting.VESTING_DURATION() + 365 days);
        assertEq(vesting.vested(alice), ALICE_AMOUNT);
        assertEq(vesting.releasable(alice), ALICE_AMOUNT);
    }

    function test_PartialReleasesAccumulateCorrectly() public {
        uint64 quarter = vesting.VESTING_DURATION() / 4;

        // Release at 25%
        vm.warp(startTs + quarter);
        vm.prank(alice);
        vesting.release();
        assertApproxEqAbs(token.balanceOf(alice), ALICE_AMOUNT / 4, 1);

        // Release at 75%
        vm.warp(startTs + 3 * quarter);
        vm.prank(alice);
        vesting.release();
        assertApproxEqAbs(token.balanceOf(alice), (ALICE_AMOUNT * 3) / 4, 1);
    }

    function test_BeforeStartReturnsZeroAndReverts() public {
        // Create a future-start schedule for charlie.
        address charlie = makeAddr("charlie");
        uint64 futureStart = uint64(block.timestamp + 30 days);

        vm.prank(owner);
        vesting.createSchedule(charlie, 100 ether, futureStart);

        // Before its start
        vm.warp(futureStart - 1);
        assertEq(vesting.vested(charlie), 0);
        assertEq(vesting.releasable(charlie), 0);

        vm.prank(charlie);
        vm.expectRevert(TokenVesting.NothingToRelease.selector);
        vesting.release();
    }

    function test_RevertWhen_NoSchedule() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(TokenVesting.NoSchedule.selector, stranger));
        vesting.release();
    }

    function test_RevertWhen_DuplicateScheduleCreated() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TokenVesting.ScheduleAlreadyExists.selector, alice));
        vesting.createSchedule(alice, 1 ether, startTs);
    }

    function test_RevertWhen_NonOwnerCreatesSchedule() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert();
        vesting.createSchedule(makeAddr("victim"), 1 ether, startTs);
    }

    function test_RevertWhen_InsufficientUnallocatedBalance() public {
        // The contract holds 40M tokens. Existing allocations = 3M. Free = 37M.
        // Attempt to allocate 38M should revert.
        vm.prank(owner);
        vm.expectRevert();
        vesting.createSchedule(makeAddr("greedy"), 38_000_000 ether, startTs);
    }

    function test_VestingDelegationGivesGovernancePower() public {
        // The vesting contract itself can delegate the team's voting power
        // to the team multisig before tokens are released. Here we verify
        // a beneficiary has voting power after release+delegation.
        vm.warp(startTs + vesting.VESTING_DURATION());

        vm.prank(alice);
        vesting.release();

        vm.prank(alice);
        token.delegate(alice);

        assertEq(token.getVotes(alice), ALICE_AMOUNT);
    }
}
