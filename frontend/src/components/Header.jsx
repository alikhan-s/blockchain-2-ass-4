import {useWeb3} from "../context/Web3Context.jsx";
import {useTokenInfo} from "../hooks/useTokenInfo.js";
import {NETWORK} from "../config.js";
import {shortAddress, formatNumber} from "./utils.js";

export function Header() {
    const {account, chainId, connect, connecting, hasMetaMask, wrongNetwork, error} = useWeb3();
    const {ethBalance, govBalance, symbol} = useTokenInfo();

    return (
        <header className="d-flex flex-wrap align-items-center justify-content-between py-3 mb-4 border-bottom">
            <a href="#" className="text-decoration-none d-flex align-items-center brand-mark fs-4">
                <span className="me-2">🏛️</span>
                MyGovernor DAO
            </a>

            <div className="d-flex align-items-center gap-3">
                {account ? (
                    <>
                        <div className="text-end small">
                            <div className="text-muted">{NETWORK.chainName} (chain {chainId})</div>
                            <div>
                                <strong>{formatNumber(ethBalance, 4)}</strong> ETH ·{" "}
                                <strong>{formatNumber(govBalance, 2)}</strong> {symbol}
                            </div>
                        </div>
                        <span className="badge text-bg-light border px-3 py-2 font-monospace">
                            {shortAddress(account)}
                        </span>
                    </>
                ) : (
                    <button
                        className="btn btn-primary"
                        onClick={connect}
                        disabled={connecting || !hasMetaMask}
                        title={hasMetaMask ? "Connect MetaMask" : "MetaMask not detected"}
                    >
                        {connecting ? "Connecting…" : "Connect Wallet"}
                    </button>
                )}
            </div>

            {(error || wrongNetwork) && (
                <div className="alert alert-warning w-100 mt-3 mb-0 py-2 small">
                    {wrongNetwork
                        ? `Wrong network. Please switch to ${NETWORK.chainName} (chainId ${NETWORK.expectedChainId}).`
                        : error}
                </div>
            )}
        </header>
    );
}
