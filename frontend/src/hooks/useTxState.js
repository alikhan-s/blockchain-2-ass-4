import {useCallback, useState} from "react";

/// Lightweight transaction state machine: idle → pending → success | error.
/// Wraps any function returning an ethers `TransactionResponse` and waits for
/// inclusion. The `state.txHash` is exposed once the user signs.
export function useTxState() {
    const [state, setState] = useState({status: "idle", txHash: null, error: null, message: null});

    const reset = useCallback(() => setState({status: "idle", txHash: null, error: null, message: null}), []);

    const run = useCallback(async (sendTx, {pendingMessage, successMessage} = {}) => {
        setState({status: "signing", txHash: null, error: null, message: pendingMessage ?? "Awaiting signature…"});
        try {
            const tx = await sendTx();
            setState({
                status: "pending",
                txHash: tx.hash,
                error: null,
                message: pendingMessage ?? "Transaction submitted, waiting for confirmation…",
            });
            const receipt = await tx.wait();
            if (!receipt || receipt.status === 0) {
                throw new Error("Transaction reverted");
            }
            setState({
                status: "success",
                txHash: tx.hash,
                error: null,
                message: successMessage ?? "Transaction confirmed.",
            });
            return receipt;
        } catch (err) {
            setState({
                status: "error",
                txHash: state.txHash,
                error: err?.shortMessage ?? err?.reason ?? err?.message ?? "Transaction failed",
                message: null,
            });
            throw err;
        }
    }, [state.txHash]);

    return {...state, run, reset, isBusy: state.status === "signing" || state.status === "pending"};
}
