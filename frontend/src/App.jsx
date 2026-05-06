import {useMemo, useState} from "react";
import {Web3Provider, useWeb3} from "./context/Web3Context.jsx";
import {Header} from "./components/Header.jsx";
import {Dashboard} from "./components/Dashboard.jsx";
import {ProposalList} from "./components/ProposalList.jsx";
import {ProposalView} from "./components/ProposalView.jsx";
import {useProposals} from "./hooks/useProposals.js";

function ConnectedApp() {
    const {account} = useWeb3();
    const [selectedId, setSelectedId] = useState(null);
    const {proposals} = useProposals();

    const selectedMeta = useMemo(
        () => (selectedId ? proposals.find((p) => p.id === selectedId) : null),
        [selectedId, proposals],
    );

    return (
        <div className="app-shell">
            <Header />

            {!account ? (
                <div className="text-center py-5">
                    <h1 className="h3 mb-3 brand-mark">MyGovernor DAO</h1>
                    <p className="text-muted mb-4">
                        Connect your wallet to view your voting power, browse proposals, and participate in
                        governance.
                    </p>
                </div>
            ) : (
                <div className="row g-4">
                    <div className="col-12">
                        <Dashboard />
                    </div>
                    <div className="col-12 col-lg-7">
                        <ProposalList onSelect={setSelectedId} />
                    </div>
                    <div className="col-12 col-lg-5">
                        {selectedId ? (
                            <ProposalView
                                proposalId={selectedId}
                                proposalMeta={selectedMeta}
                                onBack={() => setSelectedId(null)}
                            />
                        ) : (
                            <div className="card-stat p-4 text-center text-muted">
                                Select a proposal to view its tally and vote.
                            </div>
                        )}
                    </div>
                </div>
            )}
        </div>
    );
}

export default function App() {
    return (
        <Web3Provider>
            <ConnectedApp />
        </Web3Provider>
    );
}
