import {createContext, useCallback, useContext, useEffect, useMemo, useState} from "react";
import {BrowserProvider} from "ethers";
import {NETWORK} from "../config.js";

const Web3Context = createContext(null);

export function Web3Provider({children}) {
    const [provider, setProvider] = useState(null);
    const [signer, setSigner] = useState(null);
    const [account, setAccount] = useState(null);
    const [chainId, setChainId] = useState(null);
    const [error, setError] = useState(null);
    const [connecting, setConnecting] = useState(false);

    const hasMetaMask = typeof window !== "undefined" && window.ethereum !== undefined;

    const refreshSigner = useCallback(async (rawProvider) => {
        const signer_ = await rawProvider.getSigner();
        const addr = await signer_.getAddress();
        const net = await rawProvider.getNetwork();
        setSigner(signer_);
        setAccount(addr);
        setChainId(Number(net.chainId));
    }, []);

    const connect = useCallback(async () => {
        if (!hasMetaMask) {
            setError("MetaMask is not installed.");
            return;
        }
        setError(null);
        setConnecting(true);
        try {
            await window.ethereum.request({method: "eth_requestAccounts"});
            const rawProvider = new BrowserProvider(window.ethereum, "any");
            setProvider(rawProvider);
            await refreshSigner(rawProvider);
        } catch (err) {
            setError(err?.shortMessage ?? err?.message ?? "Connection failed");
        } finally {
            setConnecting(false);
        }
    }, [hasMetaMask, refreshSigner]);

    const disconnect = useCallback(() => {
        setProvider(null);
        setSigner(null);
        setAccount(null);
        setChainId(null);
    }, []);

    // Reflect MetaMask events.
    useEffect(() => {
        if (!hasMetaMask) return;
        const onAccountsChanged = (accs) => {
            if (accs.length === 0) disconnect();
            else if (provider) refreshSigner(provider);
        };
        const onChainChanged = () => {
            if (provider) refreshSigner(provider);
        };
        window.ethereum.on("accountsChanged", onAccountsChanged);
        window.ethereum.on("chainChanged", onChainChanged);
        return () => {
            window.ethereum.removeListener("accountsChanged", onAccountsChanged);
            window.ethereum.removeListener("chainChanged", onChainChanged);
        };
    }, [hasMetaMask, provider, disconnect, refreshSigner]);

    // Eagerly reconnect if MetaMask already authorised the page.
    useEffect(() => {
        if (!hasMetaMask) return;
        (async () => {
            const accs = await window.ethereum.request({method: "eth_accounts"});
            if (accs.length > 0) {
                const rawProvider = new BrowserProvider(window.ethereum, "any");
                setProvider(rawProvider);
                await refreshSigner(rawProvider);
            }
        })();
    }, [hasMetaMask, refreshSigner]);

    const wrongNetwork = chainId !== null && chainId !== NETWORK.expectedChainId;

    const value = useMemo(
        () => ({
            provider,
            signer,
            account,
            chainId,
            connecting,
            error,
            hasMetaMask,
            wrongNetwork,
            connect,
            disconnect,
        }),
        [provider, signer, account, chainId, connecting, error, hasMetaMask, wrongNetwork, connect, disconnect],
    );

    return <Web3Context.Provider value={value}>{children}</Web3Context.Provider>;
}

export function useWeb3() {
    const ctx = useContext(Web3Context);
    if (!ctx) throw new Error("useWeb3 must be used inside Web3Provider");
    return ctx;
}
