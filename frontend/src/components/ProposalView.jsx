import {useState} from "react";
import {useWeb3} from "../context/Web3Context.jsx";
import {useContracts} from "../hooks/useContracts.js";
import {useProposal} from "../hooks/useProposals.js";
import {useTxState} from "../hooks/useTxState.js";
import {VOTE_AGAINST, VOTE_ABSTAIN, VOTE_FOR} from "../abis/Governor.js";
import {StatusBadge} from "./StatusBadge.jsx";
import {TallyBar} from "./TallyBar.jsx";
import {TxToast} from "./TxToast.jsx";
import {formatNumber} from "./utils.js";

const VOTE_LABELS = {[VOTE_FOR]: "For", [VOTE_AGAINST]: "Against", [VOTE_ABSTAIN]: "Abstain"};

export function ProposalView({proposalId, proposalMeta, onBack}) {
    const {account} = useWeb3();
    const {governor} = useContracts();
    const live = useProposal(proposalId);
    const tx = useTxState();
    const [reason, setReason] = useState("");

    const cast = async (support) => {
        if (!governor) return;
        try {
            await tx.run(
                () =>
                    reason
                        ? governor.castVoteWithReason(proposalId, support, reason)
                        : governor.castVote(proposalId, support),
                {
                    pendingMessage: `Casting ${VOTE_LABELS[support]} vote…`,
                    successMessage: `Vote (${VOTE_LABELS[support]}) recorded.`,
                },
            );
            live.refresh();
        } catch {
            // tx state populated
        }
    };

    if (live.loading) {
        return (
            <div className="d-flex align-items-center gap-2 text-muted">
                <div className="spinner-border spinner-border-sm" /> Loading proposal…
            </div>
        );
    }

    const isActive = live.stateLabel === "Active";
    const isFinal = ["Executed", "Defeated", "Expired", "Canceled"].includes(live.stateLabel);

    return (
        <section>
            <button className="btn btn-link px-0 mb-3" onClick={onBack}>
                ← Back to proposals
            </button>

            <div className="card-stat p-4 mb-3">
                <div className="d-flex justify-content-between align-items-start mb-2">
                    <h2 className="h5 mb-0 me-3">{proposalMeta?.description ?? `Proposal #${proposalId.slice(0, 10)}`}</h2>
                    <StatusBadge state={live.stateLabel} />
                </div>
                <div className="text-muted small font-monospace">id #{proposalId}</div>
                <div className="mt-3 small text-muted">
                    Snapshot block {live.snapshotBlock} · Deadline block {live.deadlineBlock}
                </div>
            </div>

            <div className="card-stat p-4 mb-3">
                <div className="d-flex justify-content-between mb-2">
                    <h3 className="h6 text-muted text-uppercase mb-0">Tally</h3>
                    <div className="small text-muted">
                        Total: {formatNumber(Number(live.votes.for) + Number(live.votes.against) + Number(live.votes.abstain), 0)}
                    </div>
                </div>
                <TallyBar votes={live.votes} />
            </div>

            {isActive && account && (
                <div className="card-stat p-4 mb-3">
                    <h3 className="h6 text-muted text-uppercase mb-3">Cast your vote</h3>
                    <div className="mb-3">
                        <textarea
                            className="form-control"
                            rows={2}
                            placeholder="Optional reason (recorded on-chain in event logs)"
                            value={reason}
                            onChange={(e) => setReason(e.target.value)}
                            disabled={tx.isBusy || live.hasVoted}
                        />
                    </div>
                    <div className="d-flex flex-wrap gap-2">
                        <button
                            className="btn btn-success btn-vote"
                            disabled={tx.isBusy || live.hasVoted}
                            onClick={() => cast(VOTE_FOR)}
                        >
                            👍 For
                        </button>
                        <button
                            className="btn btn-danger btn-vote"
                            disabled={tx.isBusy || live.hasVoted}
                            onClick={() => cast(VOTE_AGAINST)}
                        >
                            👎 Against
                        </button>
                        <button
                            className="btn btn-secondary btn-vote"
                            disabled={tx.isBusy || live.hasVoted}
                            onClick={() => cast(VOTE_ABSTAIN)}
                        >
                            🤷 Abstain
                        </button>
                    </div>
                    {live.hasVoted && <div className="alert alert-info small mt-3 mb-0">You have already voted on this proposal.</div>}
                </div>
            )}

            {isFinal && (
                <div className={`alert ${live.stateLabel === "Executed" ? "alert-success" : "alert-secondary"}`}>
                    Final state: <strong>{live.stateLabel}</strong>. For{" "}
                    {formatNumber(live.votes.for, 0)} · Against {formatNumber(live.votes.against, 0)} · Abstain{" "}
                    {formatNumber(live.votes.abstain, 0)}.
                </div>
            )}

            <TxToast state={tx} />
        </section>
    );
}
