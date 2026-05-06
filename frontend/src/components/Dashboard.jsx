import {useState} from "react";
import {isAddress} from "ethers";
import {useWeb3} from "../context/Web3Context.jsx";
import {useTokenInfo} from "../hooks/useTokenInfo.js";
import {useContracts} from "../hooks/useContracts.js";
import {useTxState} from "../hooks/useTxState.js";
import {shortAddress, formatNumber} from "./utils.js";
import {TxToast} from "./TxToast.jsx";

export function Dashboard() {
    const {account} = useWeb3();
    const info = useTokenInfo();
    const {token} = useContracts();
    const tx = useTxState();
    const [target, setTarget] = useState("");
    const [validationError, setValidationError] = useState(null);

    if (!account) {
        return (
            <div className="alert alert-info">Connect your wallet to view your voting power and governance state.</div>
        );
    }

    const targetAddr = target.trim() || account;
    const targetIsValid = isAddress(targetAddr);

    const onDelegate = async () => {
        setValidationError(null);
        if (!targetIsValid) {
            setValidationError("Invalid address.");
            return;
        }
        try {
            await tx.run(() => token.delegate(targetAddr), {
                pendingMessage: `Delegating to ${shortAddress(targetAddr)}…`,
                successMessage: `Voting power delegated to ${shortAddress(targetAddr)}.`,
            });
            info.refresh();
        } catch {
            // tx state already populated
        }
    };

    return (
        <section>
            <h2 className="h4 mb-3">Your governance</h2>

            <div className="row g-3 mb-4">
                <div className="col-md-4">
                    <div className="card-stat p-3 h-100">
                        <div className="text-muted small">Voting power</div>
                        <div className="fs-3 fw-bold mt-1">{formatNumber(info.votingPower, 2)}</div>
                        <div className="text-muted small">{info.symbol} (delegated to you)</div>
                    </div>
                </div>
                <div className="col-md-4">
                    <div className="card-stat p-3 h-100">
                        <div className="text-muted small">Token balance</div>
                        <div className="fs-3 fw-bold mt-1">{formatNumber(info.govBalance, 2)}</div>
                        <div className="text-muted small">{info.symbol}</div>
                    </div>
                </div>
                <div className="col-md-4">
                    <div className="card-stat p-3 h-100">
                        <div className="text-muted small">Current delegate</div>
                        <div className="fs-5 fw-semibold mt-1 font-monospace">
                            {info.delegate ? shortAddress(info.delegate) : "Not delegated"}
                        </div>
                        <div className="text-muted small">
                            {info.delegate?.toLowerCase() === account.toLowerCase()
                                ? "You self-delegated."
                                : "Delegate to activate voting power."}
                        </div>
                    </div>
                </div>
            </div>

            <div className="card-stat p-4">
                <h3 className="h6 text-muted text-uppercase mb-3">Delegate voting power</h3>
                <div className="row g-2 align-items-center">
                    <div className="col-md-8">
                        <input
                            className="form-control font-monospace"
                            placeholder={`Delegate to address (default: yourself ${shortAddress(account)})`}
                            value={target}
                            onChange={(e) => setTarget(e.target.value)}
                            disabled={tx.isBusy}
                        />
                    </div>
                    <div className="col-md-4 d-grid">
                        <button
                            className="btn btn-primary"
                            disabled={tx.isBusy || !targetIsValid}
                            onClick={onDelegate}
                        >
                            {tx.isBusy ? (
                                <span>
                                    <span className="spinner-border spinner-border-sm me-2" />
                                    Delegating…
                                </span>
                            ) : (
                                <>Delegate to {shortAddress(targetAddr)}</>
                            )}
                        </button>
                    </div>
                </div>
                {validationError && <div className="text-danger small mt-2">{validationError}</div>}
                {info.error && <div className="text-danger small mt-2">{info.error}</div>}
            </div>

            <TxToast state={tx} />
        </section>
    );
}
