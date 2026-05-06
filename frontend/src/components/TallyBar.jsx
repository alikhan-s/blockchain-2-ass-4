import {formatNumber} from "./utils.js";

export function TallyBar({votes}) {
    const forV = Number(votes.for);
    const againstV = Number(votes.against);
    const abstainV = Number(votes.abstain);
    const total = forV + againstV + abstainV;
    const pct = (n) => (total === 0 ? 0 : (n / total) * 100);

    return (
        <div>
            <div className="tally-bar mb-2">
                <div style={{width: `${pct(forV)}%`, background: "var(--gov-success)"}} />
                <div style={{width: `${pct(againstV)}%`, background: "var(--gov-danger)"}} />
                <div style={{width: `${pct(abstainV)}%`, background: "var(--gov-muted)"}} />
            </div>
            <div className="d-flex justify-content-between small text-muted">
                <span>
                    <span className="text-success">●</span> For {formatNumber(forV, 0)}
                </span>
                <span>
                    <span className="text-danger">●</span> Against {formatNumber(againstV, 0)}
                </span>
                <span>
                    <span className="text-secondary">●</span> Abstain {formatNumber(abstainV, 0)}
                </span>
            </div>
        </div>
    );
}
