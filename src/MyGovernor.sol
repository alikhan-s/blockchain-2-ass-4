// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title MyGovernor
/// @notice Production-grade Governor for the GOV token.
/// @dev Block-number clock (inherited from token). Voting delay & period are expressed in blocks.
///
/// Parameters
/// ----------
/// - Voting delay:        7_200 blocks  (~1 day at 12s/block)
/// - Voting period:      50_400 blocks  (~1 week at 12s/block)
/// - Proposal threshold:  1% of total supply
/// - Quorum:              4% of total supply
/// - Timelock min delay:  2 days
contract MyGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /// @dev 1 day @ 12 sec/block.
    uint48 public constant INITIAL_VOTING_DELAY = 7_200;
    /// @dev 1 week @ 12 sec/block.
    uint32 public constant INITIAL_VOTING_PERIOD = 50_400;
    /// @dev 1% of 100M total supply = 1_000_000 GOV.
    uint256 public constant INITIAL_PROPOSAL_THRESHOLD = 1_000_000 ether;
    /// @dev 4% quorum (numerator over an OZ-internal denominator of 100).
    uint256 public constant INITIAL_QUORUM_NUMERATOR = 4;

    constructor(IVotes token_, TimelockController timelock_)
        Governor("MyGovernor")
        GovernorSettings(INITIAL_VOTING_DELAY, INITIAL_VOTING_PERIOD, INITIAL_PROPOSAL_THRESHOLD)
        GovernorVotes(token_)
        GovernorVotesQuorumFraction(INITIAL_QUORUM_NUMERATOR)
        GovernorTimelockControl(timelock_)
    {}

    //    OVERRIDES (multi-inheritance)

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
