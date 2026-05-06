import {useCallback, useEffect, useState} from "react";
import {formatUnits} from "ethers";
import {useWeb3} from "../context/Web3Context.jsx";
import {useContracts} from "./useContracts.js";
import {PROPOSAL_STATES} from "../abis/Governor.js";

const FROM_BLOCK_DEFAULT = 0n;

/// Loads every `ProposalCreated` event from the Governor and enriches each
/// entry with the current state, snapshot/deadline blocks, and live tally.
/// Returns `proposals` (newest first) plus a manual `refresh` function.
export function useProposals() {
    const {provider} = useWeb3();
    const {governor} = useContracts();
    const [proposals, setProposals] = useState([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    const [nonce, setNonce] = useState(0);

    const refresh = useCallback(() => setNonce((n) => n + 1), []);

    useEffect(() => {
        if (!provider || !governor) return;
        let cancelled = false;

        (async () => {
            setLoading(true);
            setError(null);
            try {
                const filter = governor.filters.ProposalCreated();
                const events = await governor.queryFilter(filter, FROM_BLOCK_DEFAULT, "latest");

                const enriched = await Promise.all(
                    events.map(async (ev) => {
                        const args = ev.args;
                        const proposalId = args.proposalId;
                        const [stateIdx, snapshot, deadline, votes] = await Promise.all([
                            governor.state(proposalId),
                            governor.proposalSnapshot(proposalId),
                            governor.proposalDeadline(proposalId),
                            governor.proposalVotes(proposalId),
                        ]);
                        return {
                            id: proposalId.toString(),
                            proposer: args.proposer,
                            description: args.description,
                            voteStart: Number(args.voteStart),
                            voteEnd: Number(args.voteEnd),
                            snapshotBlock: Number(snapshot),
                            deadlineBlock: Number(deadline),
                            stateIdx: Number(stateIdx),
                            stateLabel: PROPOSAL_STATES[Number(stateIdx)] ?? "Unknown",
                            votes: {
                                against: formatUnits(votes[0], 18),
                                for: formatUnits(votes[1], 18),
                                abstain: formatUnits(votes[2], 18),
                            },
                            txHash: ev.transactionHash,
                        };
                    }),
                );

                if (!cancelled) {
                    enriched.sort((a, b) => b.voteStart - a.voteStart);
                    setProposals(enriched);
                }
            } catch (err) {
                if (!cancelled) setError(err?.shortMessage ?? err?.message ?? "Failed to load proposals");
            } finally {
                if (!cancelled) setLoading(false);
            }
        })();

        return () => {
            cancelled = true;
        };
    }, [provider, governor, nonce]);

    return {proposals, loading, error, refresh};
}

/// Fetch a single proposal's live state + tally + whether the connected user has voted.
export function useProposal(proposalId) {
    const {governor} = useContracts();
    const {account} = useWeb3();
    const [data, setData] = useState({loading: true});
    const [nonce, setNonce] = useState(0);
    const refresh = useCallback(() => setNonce((n) => n + 1), []);

    useEffect(() => {
        if (!governor || !proposalId) return;
        let cancelled = false;
        (async () => {
            try {
                const [stateIdx, votes, snapshot, deadline, hasVoted] = await Promise.all([
                    governor.state(proposalId),
                    governor.proposalVotes(proposalId),
                    governor.proposalSnapshot(proposalId),
                    governor.proposalDeadline(proposalId),
                    account ? governor.hasVoted(proposalId, account) : Promise.resolve(false),
                ]);
                if (cancelled) return;
                setData({
                    loading: false,
                    stateIdx: Number(stateIdx),
                    stateLabel: PROPOSAL_STATES[Number(stateIdx)] ?? "Unknown",
                    snapshotBlock: Number(snapshot),
                    deadlineBlock: Number(deadline),
                    hasVoted,
                    votes: {
                        against: formatUnits(votes[0], 18),
                        for: formatUnits(votes[1], 18),
                        abstain: formatUnits(votes[2], 18),
                    },
                });
            } catch (err) {
                if (!cancelled) setData({loading: false, error: err?.shortMessage ?? err?.message});
            }
        })();
        return () => {
            cancelled = true;
        };
    }, [governor, account, proposalId, nonce]);

    return {...data, refresh};
}
