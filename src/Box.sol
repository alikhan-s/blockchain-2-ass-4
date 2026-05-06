// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title Box
/// @notice Minimal DAO-managed contract: a single uint256 value writable only by the Timelock.
/// @dev Used as a canonical end-to-end target to demonstrate that a Governor proposal,
///      after going through voting, queueing, and execution, can mutate external state.
contract Box {
    error NotTimelock(address caller);
    error ZeroAddress();

    address public immutable timelock;
    uint256 private _value;

    event ValueChanged(uint256 oldValue, uint256 newValue);

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert NotTimelock(msg.sender);
        _;
    }

    constructor(address timelock_) {
        if (timelock_ == address(0)) revert ZeroAddress();
        timelock = timelock_;
    }

    /// @notice Update the stored value. DAO-only.
    function store(uint256 newValue) external onlyTimelock {
        emit ValueChanged(_value, newValue);
        _value = newValue;
    }

    /// @notice Read the stored value.
    function retrieve() external view returns (uint256) {
        return _value;
    }
}
