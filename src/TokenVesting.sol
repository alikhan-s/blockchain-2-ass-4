// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TokenVesting
/// @notice Linear vesting of governance tokens for team beneficiaries over a 12-month schedule.
/// @dev Follows Checks-Effects-Interactions and is protected by ReentrancyGuard.
contract TokenVesting is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error ZeroAmount();
    error ScheduleAlreadyExists(address beneficiary);
    error NoSchedule(address beneficiary);
    error NothingToRelease();
    error InsufficientUnallocatedBalance(uint256 requested, uint256 available);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Vesting duration: 12 months (365 days).
    uint64 public constant VESTING_DURATION = 365 days;

    /*//////////////////////////////////////////////////////////////
                                  TYPES
    //////////////////////////////////////////////////////////////*/

    struct Schedule {
        uint128 totalAmount;
        uint128 released;
        uint64 start;
    }

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    IERC20 public immutable token;

    mapping(address beneficiary => Schedule) private _schedules;

    /// @notice Sum of `totalAmount` across all schedules ever created.
    uint256 public totalAllocated;

    /// @notice Cumulative amount of tokens released to beneficiaries so far.
    uint256 public totalReleased;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ScheduleCreated(address indexed beneficiary, uint256 amount, uint64 start, uint64 duration);
    event TokensReleased(address indexed beneficiary, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address token_, address owner_) Ownable(owner_) {
        if (token_ == address(0) || owner_ == address(0)) revert ZeroAddress();
        token = IERC20(token_);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Create a linear vesting schedule for a beneficiary.
    /// @param beneficiary Address that will be able to claim vested tokens.
    /// @param amount Total amount of tokens to vest.
    /// @param start Unix timestamp at which the linear vest begins. Pass 0 for `block.timestamp`.
    /// @dev The contract must already hold enough tokens to cover existing outstanding commitments
    ///      plus the new `amount`. Schedules cannot be overwritten.
    function createSchedule(address beneficiary, uint256 amount, uint64 start) external onlyOwner {
        // Checks
        if (beneficiary == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (_schedules[beneficiary].totalAmount != 0) revert ScheduleAlreadyExists(beneficiary);

        uint256 outstanding_ = totalAllocated - totalReleased;
        uint256 balance = token.balanceOf(address(this));
        if (balance < outstanding_ + amount) {
            revert InsufficientUnallocatedBalance({requested: amount, available: balance - outstanding_});
        }

        uint64 effectiveStart = start == 0 ? uint64(block.timestamp) : start;

        // Effects
        _schedules[beneficiary] = Schedule({totalAmount: uint128(amount), released: 0, start: effectiveStart});
        totalAllocated += amount;

        emit ScheduleCreated(beneficiary, amount, effectiveStart, VESTING_DURATION);
    }

    /*//////////////////////////////////////////////////////////////
                          BENEFICIARY ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Release all tokens currently vested to the caller.
    function release() external nonReentrant {
        Schedule memory s = _schedules[msg.sender];
        if (s.totalAmount == 0) revert NoSchedule(msg.sender);

        uint256 vested_ = _vestedAmount(s, uint64(block.timestamp));
        uint256 amount = vested_ - s.released;
        if (amount == 0) revert NothingToRelease();

        // Effects
        _schedules[msg.sender].released = uint128(s.released + amount);
        totalReleased += amount;

        // Interactions
        token.safeTransfer(msg.sender, amount);

        emit TokensReleased(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function scheduleOf(address beneficiary) external view returns (Schedule memory) {
        return _schedules[beneficiary];
    }

    /// @notice Tokens currently releasable to `beneficiary`.
    function releasable(address beneficiary) external view returns (uint256) {
        Schedule memory s = _schedules[beneficiary];
        if (s.totalAmount == 0) return 0;
        return _vestedAmount(s, uint64(block.timestamp)) - s.released;
    }

    /// @notice Total amount vested to `beneficiary` at the current time (released + still-claimable).
    function vested(address beneficiary) external view returns (uint256) {
        return _vestedAmount(_schedules[beneficiary], uint64(block.timestamp));
    }

    /// @notice Outstanding (unreleased) tokens still owed to all beneficiaries.
    function outstanding() external view returns (uint256) {
        return totalAllocated - totalReleased;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _vestedAmount(Schedule memory s, uint64 timestamp) internal pure returns (uint256) {
        if (s.totalAmount == 0 || timestamp <= s.start) return 0;
        uint64 elapsed = timestamp - s.start;
        if (elapsed >= VESTING_DURATION) return s.totalAmount;
        return (uint256(s.totalAmount) * elapsed) / VESTING_DURATION;
    }
}
