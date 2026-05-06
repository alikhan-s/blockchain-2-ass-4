// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title GovernanceToken
/// @notice ERC20 governance token with EIP-2612 permit and vote delegation (ERC20Votes).
/// @dev Total supply minted once in constructor and split between Team / Treasury / Airdrop / Liquidity.
contract GovernanceToken is ERC20, ERC20Permit, ERC20Votes {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error DuplicateRecipient();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Total supply: 100,000,000 tokens (18 decimals).
    uint256 public constant TOTAL_SUPPLY = 100_000_000 ether;

    /// @notice Allocations expressed in basis points (10000 = 100%).
    uint16 public constant TEAM_BPS = 4_000; // 40%
    uint16 public constant TREASURY_BPS = 3_000; // 30%
    uint16 public constant AIRDROP_BPS = 2_000; // 20%
    uint16 public constant LIQUIDITY_BPS = 1_000; // 10%
    uint16 private constant _BPS_DENOMINATOR = 10_000;

    /// @notice Absolute amounts derived from basis points.
    uint256 public constant TEAM_ALLOCATION = (TOTAL_SUPPLY * TEAM_BPS) / _BPS_DENOMINATOR;
    uint256 public constant TREASURY_ALLOCATION = (TOTAL_SUPPLY * TREASURY_BPS) / _BPS_DENOMINATOR;
    uint256 public constant AIRDROP_ALLOCATION = (TOTAL_SUPPLY * AIRDROP_BPS) / _BPS_DENOMINATOR;
    uint256 public constant LIQUIDITY_ALLOCATION = (TOTAL_SUPPLY * LIQUIDITY_BPS) / _BPS_DENOMINATOR;

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    address public immutable teamVesting;
    address public immutable treasury;
    address public immutable airdrop;
    address public immutable liquidity;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param teamVesting_ Vesting contract receiving 40% (linear unlock).
    /// @param treasury_ DAO treasury receiving 30%.
    /// @param airdrop_ Airdrop distributor receiving 20%.
    /// @param liquidity_ Liquidity provider receiving 10%.
    constructor(address teamVesting_, address treasury_, address airdrop_, address liquidity_)
        ERC20("Governance Token", "GOV")
        ERC20Permit("Governance Token")
    {
        if (teamVesting_ == address(0) || treasury_ == address(0) || airdrop_ == address(0) || liquidity_ == address(0))
        {
            revert ZeroAddress();
        }
        if (
            teamVesting_ == treasury_ || teamVesting_ == airdrop_ || teamVesting_ == liquidity_
                || treasury_ == airdrop_ || treasury_ == liquidity_ || airdrop_ == liquidity_
        ) {
            revert DuplicateRecipient();
        }

        teamVesting = teamVesting_;
        treasury = treasury_;
        airdrop = airdrop_;
        liquidity = liquidity_;

        _mint(teamVesting_, TEAM_ALLOCATION);
        _mint(treasury_, TREASURY_ALLOCATION);
        _mint(airdrop_, AIRDROP_ALLOCATION);
        _mint(liquidity_, LIQUIDITY_ALLOCATION);
    }

    /*//////////////////////////////////////////////////////////////
                          REQUIRED OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ERC20
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    /// @inheritdoc Nonces
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
