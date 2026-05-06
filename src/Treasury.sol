// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title Treasury
/// @notice Custodial vault for ETH and ERC-20 assets. Every outbound action is gated by
///         `onlyTimelock` so that funds can only move when a DAO proposal has been
///         approved, queued, and executed by the `TimelockController`.
/// @dev    The Treasury is intentionally separated from the `TimelockController` itself.
///         While many DAOs collapse the two for simplicity, isolating custody from the
///         executor reduces blast radius: a bug in the Governor cannot enable arbitrary
///         draining unless the Timelock is also exploited.
contract Treasury is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NotTimelock(address caller);
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientETH(uint256 requested, uint256 available);
    error CallFailed();

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The TimelockController is the sole privileged caller.
    address public immutable timelock;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ETHReceived(address indexed from, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    event ArbitraryCall(address indexed target, uint256 value, bytes data);

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyTimelock() {
        if (msg.sender != timelock) revert NotTimelock(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address timelock_) {
        if (timelock_ == address(0)) revert ZeroAddress();
        timelock = timelock_;
    }

    /*//////////////////////////////////////////////////////////////
                              ETH HANDLING
    //////////////////////////////////////////////////////////////*/

    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    /// @notice Send ETH to `to`. DAO-only.
    function withdrawETH(address payable to, uint256 amount) external onlyTimelock nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 bal = address(this).balance;
        if (bal < amount) revert InsufficientETH(amount, bal);

        emit ETHWithdrawn(to, amount);
        Address.sendValue(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC-20 HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Send `amount` of `token` to `to`. DAO-only.
    function withdrawERC20(IERC20 token, address to, uint256 amount) external onlyTimelock nonReentrant {
        if (address(token) == address(0) || to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        emit ERC20Withdrawn(address(token), to, amount);
        token.safeTransfer(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ARBITRARY EXECUTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Execute an arbitrary low-level call. Reserved for parameter updates and
    ///         contract upgrades that are not expressible via `withdraw*`.
    /// @dev    DAO-only. Forwards `value` ETH from this contract.
    function execute(address target, uint256 value, bytes calldata data)
        external
        onlyTimelock
        nonReentrant
        returns (bytes memory result)
    {
        if (target == address(0)) revert ZeroAddress();
        emit ArbitraryCall(target, value, data);

        bool ok;
        (ok, result) = target.call{value: value}(data);
        if (!ok) revert CallFailed();
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function ethBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function tokenBalance(IERC20 token) external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
