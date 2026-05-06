import {useMemo} from "react";
import {Contract} from "ethers";
import {useWeb3} from "../context/Web3Context.jsx";
import {CONTRACTS} from "../config.js";
import {GOVERNANCE_TOKEN_ABI} from "../abis/GovernanceToken.js";
import {GOVERNOR_ABI} from "../abis/Governor.js";

/// Returns `{ token, governor }` contract instances wired to the active signer
/// (for writes) and to the provider (for reads). Returns nulls until the wallet
/// is connected.
export function useContracts() {
    const {signer, provider} = useWeb3();

    return useMemo(() => {
        const runner = signer ?? provider;
        if (!runner) return {token: null, governor: null};
        return {
            token: new Contract(CONTRACTS.governanceToken, GOVERNANCE_TOKEN_ABI, runner),
            governor: new Contract(CONTRACTS.governor, GOVERNOR_ABI, runner),
        };
    }, [signer, provider]);
}
