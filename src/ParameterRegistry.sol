// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ParameterRegistry
/// @notice Tiny owned key-value store used to demonstrate governance-controlled parameter
///         updates: ownership is transferred to the `TimelockController` so only DAO
///         proposals (executed by the timelock) can mutate `value`.
contract ParameterRegistry is Ownable {
    error ZeroValue();

    uint256 public value;

    event ValueUpdated(uint256 oldValue, uint256 newValue);

    constructor(address owner_, uint256 initialValue_) Ownable(owner_) {
        value = initialValue_;
    }

    function setValue(uint256 newValue) external onlyOwner {
        if (newValue == 0) revert ZeroValue();
        emit ValueUpdated(value, newValue);
        value = newValue;
    }
}
