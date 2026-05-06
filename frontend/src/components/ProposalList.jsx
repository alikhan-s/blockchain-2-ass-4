import {useProposals} from "../hooks/useProposals.js";
import {StatusBadge} from "./StatusBadge.jsx";
import {TallyBar} from "./TallyBar.jsx";
import {shortAddress} from "./utils.js";

const TERMINAL = new Set(["Executed", "Defeated", "Canceled", "Expired"]);

export function ProposalList({onSelect}) {
    const {proposals, loading, error, refresh} = useProposals();

    if (loading) {
        return (
            <div className="d-flex align-items-center gap-2 text-muted">
                <div className="spinner-border spinner-border-sm" /> Loading proposals…
            </div>
        );
    }
    if (error) {
        return (
            <div className="alert alert-danger d-flex justify-content-between">
                <span>{error}</span>
                <button className="btn btn-sm btn-outline-danger" onClick={refresh}>
                    Retry
                </button>
            </div>
        );
    }
    if (proposals.length === 0) {
        return <div className="alert alert-light border">No proposals yet.</div>;
    }

    const active = proposals.filter((p) => !TERMINAL.has(p.stateLabel));
    const past = proposals.filter((p) => TERMINAL.has(p.stateLabel));

    return (
        <section>
            <div className="d-flex align-items-center justify-content-between mb-2">
                <h2 className="h4 mb-0">Proposals</h2>
                <button className="btn btn-sm btn-outline-secondary" onClick={refresh}>
                    Refresh
                </button>
            </div>

            {active.length > 0 && (
                <>
                    <h3 className="h6 text-uppercase text-muted mb-2 mt-3">Active / In progress</h3>
                    {active.map((p) => (
                        <ProposalRow key={p.id} proposal={p} onSelect={onSelect} />
                    ))}
                </>
            )}

            {past.length > 0 && (
                <>
                    <h3 className="h6 text-uppercase text-muted mb-2 mt-4">Past proposals</h3>
                    {past.map((p) => (
                        <ProposalRow key={p.id} proposal={p} onSelect={onSelect} />
                    ))}
                </>
            )}
        </section>
    );
}

function ProposalRow({proposal, onSelect}) {
    const title = proposal.description.split("\n")[0].slice(0, 120);
    return (
        <div className="proposal-row" onClick={() => onSelect(proposal.id)}>
            <div className="d-flex justify-content-between align-items-start mb-2">
                <div className="me-3">
                    <div className="fw-semibold">{title || `Proposal #${proposal.id.slice(0, 8)}…`}</div>
                    <div className="small text-muted">
                        by <span className="font-monospace">{shortAddress(proposal.proposer)}</span> · id{" "}
                        <span className="font-monospace">#{proposal.id.slice(0, 10)}…</span>
                    </div>
                </div>
                <StatusBadge state={proposal.stateLabel} />
            </div>
            <TallyBar votes={proposal.votes} />
        </div>
    );
}
