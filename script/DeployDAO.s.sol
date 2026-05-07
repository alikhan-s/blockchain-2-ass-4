// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console2} from "forge-std/Script.sol";

import {GovernanceToken} from "../src/GovernanceToken.sol";
import {TokenVesting} from "../src/TokenVesting.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Treasury} from "../src/Treasury.sol";
import {Box} from "../src/Box.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title DeployDAO
/// @notice Foundry script that deploys the full DAO stack in canonical order:
///         (TokenVesting ->) Token -> Timelock -> Governor -> Treasury -> Box
///         and wires every role correctly, leaving the system fully self-sovereign.
///
/// @dev    Required env vars (set in `.env` and source it before running, or pass via -e):
///           - DEPLOYER_PRIVATE_KEY  : 0x-prefixed private key of the deployer EOA
///           - TREASURY_EOA          : initial holder of the 30% treasury allocation
///                                     (transfer to the actual Timelock can be done later by DAO)
///           - AIRDROP_RECIPIENT     : initial holder of the 20% airdrop allocation
///           - LIQUIDITY_RECIPIENT   : initial holder of the 10% liquidity allocation
///         Optional env vars:
///           - TIMELOCK_DELAY        : seconds (default 172800 = 2 days)
///           - OPEN_EXECUTOR         : "true" to grant EXECUTOR_ROLE to address(0)
///                                     (anyone can execute queued proposals after the delay).
///                                     "false" to restrict execution to the Governor only.
///                                     Default: "true" (the most common production pattern).
contract DeployDAO is Script {

    uint256 internal constant DEFAULT_TIMELOCK_DELAY = 2 days;

    struct Deployment {
        TokenVesting vesting;
        GovernanceToken token;
        TimelockController timelock;
        MyGovernor governor;
        Treasury treasury;
        Box box;
    }

    function run() external returns (Deployment memory dep) {

        uint256 pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address treasuryEoa = vm.envAddress("TREASURY_EOA");
        address airdrop = vm.envAddress("AIRDROP_RECIPIENT");
        address liquidity = vm.envAddress("LIQUIDITY_RECIPIENT");
        uint256 timelockDelay = _envOrDefaultUint("TIMELOCK_DELAY", DEFAULT_TIMELOCK_DELAY);
        bool openExecutor = _envOrDefaultBool("OPEN_EXECUTOR", true);

        require(treasuryEoa != address(0), "TREASURY_EOA missing");
        require(airdrop != address(0), "AIRDROP_RECIPIENT missing");
        require(liquidity != address(0), "LIQUIDITY_RECIPIENT missing");

        console2.log("==========================================");
        console2.log(" DAO DEPLOYMENT");
        console2.log("==========================================");
        console2.log("Deployer:      ", deployer);
        console2.log("Chain id:      ", block.chainid);
        console2.log("Timelock delay:", timelockDelay);
        console2.log("Open executor: ", openExecutor);
        console2.log("");

        vm.startBroadcast(pk);

        //    Vesting + Token (handles the constructor circular dep)
        //
        //    The token's constructor mints 40% directly to the vesting
        //    contract, so vesting must exist first. To avoid a 2-step
        //    setup we predict the token's CREATE address using the
        //    deployer nonce.
        uint64 nonce = vm.getNonce(deployer);
        address predictedToken = vm.computeCreateAddress(deployer, nonce + 1);

        dep.vesting = new TokenVesting(predictedToken, deployer);
        dep.token = new GovernanceToken(address(dep.vesting), treasuryEoa, airdrop, liquidity);
        require(address(dep.token) == predictedToken, "predicted token addr mismatch");

        console2.log("[1] TokenVesting    :", address(dep.vesting));
        console2.log("[2] GovernanceToken :", address(dep.token));

        //    Timelock — proposers/executors are wired AFTER the
        //    Governor exists. Deployer is the temporary admin so we
        //    can call grantRole, then we revoke it.
        address[] memory empty;
        dep.timelock = new TimelockController(timelockDelay, empty, empty, deployer);
        console2.log("[3] TimelockController:", address(dep.timelock));

        //    Governor
        dep.governor = new MyGovernor(IVotes(address(dep.token)), dep.timelock);
        console2.log("[4] MyGovernor      :", address(dep.governor));

        //    Wiring roles on the Timelock
        bytes32 PROPOSER = dep.timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR = dep.timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER = dep.timelock.CANCELLER_ROLE();
        bytes32 ADMIN = dep.timelock.DEFAULT_ADMIN_ROLE();

        dep.timelock.grantRole(PROPOSER, address(dep.governor));
        dep.timelock.grantRole(CANCELLER, address(dep.governor));

        if (openExecutor) {
            // Granting EXECUTOR to address(0) is the OZ-encoded way to make the
            // role open: anyone can execute a queued proposal after the delay.
            dep.timelock.grantRole(EXECUTOR, address(0));
            console2.log("    EXECUTOR_ROLE -> address(0) (open executor)");
        } else {
            dep.timelock.grantRole(EXECUTOR, address(dep.governor));
            console2.log("    EXECUTOR_ROLE -> governor (restricted)");
        }

        //    Final hand-off: revoke admin from deployer.
        dep.timelock.revokeRole(ADMIN, deployer);
        console2.log("    DEFAULT_ADMIN_ROLE revoked from deployer");

        //    Treasury & Box (DAO-managed contracts)
        dep.treasury = new Treasury(address(dep.timelock));
        dep.box = new Box(address(dep.timelock));
        console2.log("[5] Treasury        :", address(dep.treasury));
        console2.log("[6] Box             :", address(dep.box));

        vm.stopBroadcast();

        //    Post-deploy invariants (read-only, no broadcast)
        _assertInvariants(dep, deployer, openExecutor);

        console2.log("");
        console2.log("==========================================");
        console2.log(" DEPLOYMENT COMPLETE");
        console2.log("==========================================");
    }

    //    INVARIANT CHECKS

    function _assertInvariants(Deployment memory dep, address deployer, bool openExecutor) internal view {
        require(dep.token.totalSupply() == 100_000_000 ether, "supply != 100M");
        require(dep.token.balanceOf(address(dep.vesting)) == 40_000_000 ether, "vesting bal != 40M");

        require(address(dep.governor.timelock()) == address(dep.timelock), "governor.timelock");
        require(dep.governor.votingDelay() == 7_200, "voting delay");
        require(dep.governor.votingPeriod() == 50_400, "voting period");
        require(dep.governor.proposalThreshold() == 1_000_000 ether, "threshold");
        require(dep.governor.quorumNumerator() == 4, "quorum numerator");

        require(
            dep.timelock.hasRole(dep.timelock.PROPOSER_ROLE(), address(dep.governor)),
            "governor lacks PROPOSER_ROLE"
        );
        require(
            dep.timelock.hasRole(dep.timelock.CANCELLER_ROLE(), address(dep.governor)),
            "governor lacks CANCELLER_ROLE"
        );
        if (openExecutor) {
            require(dep.timelock.hasRole(dep.timelock.EXECUTOR_ROLE(), address(0)), "executor not open");
        } else {
            require(
                dep.timelock.hasRole(dep.timelock.EXECUTOR_ROLE(), address(dep.governor)),
                "governor lacks EXECUTOR_ROLE"
            );
        }
        require(!dep.timelock.hasRole(dep.timelock.DEFAULT_ADMIN_ROLE(), deployer), "deployer still admin");

        require(dep.treasury.timelock() == address(dep.timelock), "treasury.timelock");
        require(dep.box.timelock() == address(dep.timelock), "box.timelock");
    }

    //    ENV HELPERS

    function _envOrDefaultUint(string memory key, uint256 fallbackValue) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 v) {
            return v;
        } catch {
            return fallbackValue;
        }
    }

    function _envOrDefaultBool(string memory key, bool fallbackValue) internal view returns (bool) {
        try vm.envBool(key) returns (bool v) {
            return v;
        } catch {
            return fallbackValue;
        }
    }
}
