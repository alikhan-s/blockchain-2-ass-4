import {useCallback, useEffect, useState} from "react";
import {formatUnits} from "ethers";
import {useWeb3} from "../context/Web3Context.jsx";
import {useContracts} from "./useContracts.js";

const ZERO = "0x0000000000000000000000000000000000000000";

/// Fetches the connected wallet's ETH balance, GOV balance, voting power, and
/// current delegate. Re-fetches whenever a refresh nonce is bumped.
export function useTokenInfo() {
    const {provider, account} = useWeb3();
    const {token} = useContracts();
    const [data, setData] = useState({
        ethBalance: null,
        govBalance: null,
        votingPower: null,
        delegate: null,
        symbol: "GOV",
        decimals: 18,
        loading: true,
        error: null,
    });
    const [nonce, setNonce] = useState(0);

    const refresh = useCallback(() => setNonce((n) => n + 1), []);

    useEffect(() => {
        if (!provider || !token || !account) {
            setData((d) => ({...d, loading: false}));
            return;
        }
        let cancelled = false;
        (async () => {
            setData((d) => ({...d, loading: true, error: null}));
            try {
                const [ethBal, govBal, votes, delegateAddr, decimals, symbol] = await Promise.all([
                    provider.getBalance(account),
                    token.balanceOf(account),
                    token.getVotes(account),
                    token.delegates(account),
                    token.decimals().catch(() => 18),
                    token.symbol().catch(() => "GOV"),
                ]);
                if (cancelled) return;
                setData({
                    ethBalance: formatUnits(ethBal, 18),
                    govBalance: formatUnits(govBal, decimals),
                    votingPower: formatUnits(votes, decimals),
                    delegate: delegateAddr === ZERO ? null : delegateAddr,
                    symbol,
                    decimals: Number(decimals),
                    loading: false,
                    error: null,
                });
            } catch (err) {
                if (cancelled) return;
                setData((d) => ({...d, loading: false, error: err?.shortMessage ?? err?.message ?? "read failed"}));
            }
        })();
        return () => {
            cancelled = true;
        };
    }, [provider, token, account, nonce]);

    return {...data, refresh};
}
