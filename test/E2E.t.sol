// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console2} from "forge-std/Test.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Treasury} from "../src/Treasury.sol";
import {Box} from "../src/Box.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev Full DAO stack including Treasury & Box. Mirrors the structure of `DAOFixture`
///      in `Governor.t.sol` but adds the two new managed contracts as DAO-controlled targets.
abstract contract E2EFixture is Test {
    uint256 internal constant TOTAL_SUPPLY = 100_000_000 ether;
    uint256 internal constant ALICE_VOTES = 5_000_000 ether;
    uint256 internal constant BOB_VOTES = 3_000_000 ether;
    uint256 internal constant TIMELOCK_DELAY = 2 days;

    address internal deployer = makeAddr("deployer");
    address internal treasuryEoa = makeAddr("treasuryEoa");
    address internal airdrop = makeAddr("airdrop");
    address internal liquidity = makeAddr("liquidity");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    GovernanceToken internal token;
    TokenVesting internal vesting;
    TimelockController internal timelock;
    MyGovernor internal governor;
    Treasury internal treasury;
    Box internal box;

    function setUp() public virtual {
        vm.startPrank(deployer);

        // Token + vesting (CREATE-address prediction).
        uint64 startNonce = vm.getNonce(deployer);
        address predictedToken = vm.computeCreateAddress(deployer, startNonce + 1);
        vesting = new TokenVesting(predictedToken, deployer);
        token = new GovernanceToken(address(vesting), treasuryEoa, airdrop, liquidity);
        require(address(token) == predictedToken, "create-address mismatch");

        // Timelock + Governor.
        address[] memory empty;
        timelock = new TimelockController(TIMELOCK_DELAY, empty, empty, deployer);
        governor = new MyGovernor(IVotes(address(token)), timelock);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.revokeRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopPrank();

        // DAO-managed contracts: Treasury & Box. Both gated by `onlyTimelock`.
        treasury = new Treasury(address(timelock));
        box = new Box(address(timelock));

        // Distribute voting power.
        vm.startPrank(treasuryEoa);
        token.transfer(alice, ALICE_VOTES);
        token.transfer(bob, BOB_VOTES);
        vm.stopPrank();
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.roll(block.number + 1);
    }

    //    GOVERNANCE HELPER

    /// @dev Run a single-action proposal end-to-end: propose -> wait -> vote For -> wait ->
    ///      queue -> wait timelock -> execute. Returns the proposal id.
    function _runProposal(address target, uint256 value, bytes memory data, string memory description)
        internal
        returns (uint256 proposalId)
    {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = target;
        values[0] = value;
        calldatas[0] = data;
        bytes32 descHash = keccak256(bytes(description));

        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, description);

        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);
        governor.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        governor.execute(targets, values, calldatas, descHash);
    }
}

//    E2E: Box.store(42)

contract BoxE2ETest is E2EFixture {
    /// @notice The canonical E2E flow requested in the spec.
    function test_E2E_DAOStoresFortyTwoInBox() public {
        console2.log("=== E2E: DAO -> Box.store(42) ===");
        assertEq(box.retrieve(), 0, "initial value");

        uint256 proposalId =
            _runProposal(address(box), 0, abi.encodeCall(box.store, (42)), "Set Box value to 42 (the answer)");

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed), "executed");
        assertEq(box.retrieve(), 42, "Box value updated by DAO");

        console2.log("Final box.retrieve() = %s", box.retrieve());
    }

    /// @notice Direct calls to Box.store outside the DAO must always revert.
    function test_RevertWhen_NonTimelockCallsBoxStore() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Box.NotTimelock.selector, alice));
        box.store(42);

        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(Box.NotTimelock.selector, deployer));
        box.store(99);
    }

    /// @notice Multiple DAO-driven updates accumulate in the expected order.
    function test_E2E_MultipleStoreUpdates() public {
        _runProposal(address(box), 0, abi.encodeCall(box.store, (42)), "set 42");
        assertEq(box.retrieve(), 42);

        _runProposal(address(box), 0, abi.encodeCall(box.store, (1337)), "set 1337");
        assertEq(box.retrieve(), 1337);
    }
}

//    E2E: Treasury

contract TreasuryE2ETest is E2EFixture {
    function test_TreasuryAcceptsETHViaReceive() public {
        address sender = makeAddr("sender");
        vm.deal(sender, 10 ether);
        vm.prank(sender);
        (bool ok,) = address(treasury).call{value: 5 ether}("");
        assertTrue(ok);
        assertEq(treasury.ethBalance(), 5 ether);
    }

    function test_RevertWhen_NonTimelockWithdrawsETH() public {
        vm.deal(address(treasury), 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Treasury.NotTimelock.selector, alice));
        treasury.withdrawETH(payable(alice), 1 ether);
    }

    function test_RevertWhen_NonTimelockWithdrawsERC20() public {
        vm.prank(treasuryEoa);
        token.transfer(address(treasury), 1_000 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Treasury.NotTimelock.selector, alice));
        treasury.withdrawERC20(IERC20(address(token)), alice, 1 ether);
    }

    /// @notice Full DAO flow: deposit ETH, propose withdrawal, execute, assert balances.
    function test_E2E_DAOWithdrawsETHFromTreasury() public {
        // Pre-fund treasury.
        vm.deal(address(this), 10 ether);
        (bool ok,) = address(treasury).call{value: 10 ether}("");
        assertTrue(ok);
        assertEq(treasury.ethBalance(), 10 ether);

        address payable grantee = payable(makeAddr("grantee"));
        uint256 grantAmount = 4 ether;

        _runProposal(
            address(treasury),
            0,
            abi.encodeCall(treasury.withdrawETH, (grantee, grantAmount)),
            "Treasury: send 4 ETH grant"
        );

        assertEq(grantee.balance, grantAmount, "grantee got ETH");
        assertEq(treasury.ethBalance(), 6 ether, "treasury debited");
    }

    /// @notice Full DAO flow for ERC-20 withdrawal from the treasury.
    function test_E2E_DAOWithdrawsERC20FromTreasury() public {
        // Send 1M GOV into the treasury.
        vm.prank(treasuryEoa);
        token.transfer(address(treasury), 1_000_000 ether);
        assertEq(token.balanceOf(address(treasury)), 1_000_000 ether);

        address grantee = makeAddr("erc20Grantee");
        uint256 grantAmount = 250_000 ether;

        _runProposal(
            address(treasury),
            0,
            abi.encodeCall(treasury.withdrawERC20, (IERC20(address(token)), grantee, grantAmount)),
            "Treasury: pay 250k GOV grant"
        );

        assertEq(token.balanceOf(grantee), grantAmount);
        assertEq(token.balanceOf(address(treasury)), 750_000 ether);
    }

    /// @notice Treasury can perform arbitrary calls (e.g. parameter updates) — DAO-only.
    function test_E2E_DAOExecutesArbitraryCallViaTreasury() public {
        // Treasury -> Box.store(7) via the arbitrary execute() pathway. The Box still
        // requires `msg.sender == timelock`, so this must revert (Treasury is the caller,
        // not the Timelock). Verifies the trust boundary remains tight.
        bytes memory data = abi.encodeCall(box.store, (7));

        // Build proposal: Timelock -> Treasury.execute(Box, 0, data)
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(treasury.execute, (address(box), 0, data));
        string memory desc = "Treasury attempts Box.store(7)";
        bytes32 descHash = keccak256(bytes(desc));

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, desc);
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.prank(alice);
        governor.castVote(proposalId, 1);
        vm.prank(bob);
        governor.castVote(proposalId, 1);

        vm.roll(block.number + governor.votingPeriod() + 1);
        governor.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Execute should revert at the Box level: Treasury != Timelock.
        // The whole TX bubbles up as a TimelockUnexpectedOperationState / GovernorFailedCall.
        vm.expectRevert();
        governor.execute(targets, values, calldatas, descHash);
        assertEq(box.retrieve(), 0, "Box untouched -- trust boundary holds");
    }
}
