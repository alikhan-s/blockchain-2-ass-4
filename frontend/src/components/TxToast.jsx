import {NETWORK} from "../config.js";

const TITLES = {
    signing: "Awaiting signature",
    pending: "Transaction pending",
    success: "Transaction confirmed",
    error: "Transaction failed",
};

const VARIANTS = {
    signing: "border-warning text-warning-emphasis bg-warning-subtle",
    pending: "border-primary text-primary-emphasis bg-primary-subtle",
    success: "border-success text-success-emphasis bg-success-subtle",
    error: "border-danger text-danger-emphasis bg-danger-subtle",
};

export function TxToast({state}) {
    if (!state || state.status === "idle") return null;
    const title = TITLES[state.status] ?? "Transaction";
    const variant = VARIANTS[state.status] ?? "";

    const explorerHref =
        state.txHash && NETWORK.blockExplorer ? `${NETWORK.blockExplorer.replace(/\/$/, "")}/tx/${state.txHash}` : null;

    return (
        <div className={`tx-toast border rounded-3 p-3 shadow-sm ${variant}`} role="status">
            <div className="d-flex align-items-center gap-2 mb-1">
                {(state.status === "signing" || state.status === "pending") && (
                    <div className="spinner-border spinner-border-sm" />
                )}
                <strong>{title}</strong>
            </div>
            {state.message && <div className="small mb-1">{state.message}</div>}
            {state.error && <div className="small mb-1">{state.error}</div>}
            {state.txHash && (
                <div className="small text-truncate">
                    {explorerHref ? (
                        <a href={explorerHref} target="_blank" rel="noreferrer">
                            tx: {state.txHash.slice(0, 10)}…
                        </a>
                    ) : (
                        <span>tx: {state.txHash.slice(0, 10)}…</span>
                    )}
                </div>
            )}
        </div>
    );
}
