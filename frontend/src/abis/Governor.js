// Minimal ABI for MyGovernor (Governor + Settings + CountingSimple + TimelockControl).
export const GOVERNOR_ABI = [
    "function name() view returns (string)",
    "function votingDelay() view returns (uint256)",
    "function votingPeriod() view returns (uint256)",
    "function proposalThreshold() view returns (uint256)",
    "function quorum(uint256 timepoint) view returns (uint256)",
    "function state(uint256 proposalId) view returns (uint8)",
    "function proposalSnapshot(uint256 proposalId) view returns (uint256)",
    "function proposalDeadline(uint256 proposalId) view returns (uint256)",
    "function proposalVotes(uint256 proposalId) view returns (uint256 against, uint256 forVotes, uint256 abstain)",
    "function proposalEta(uint256 proposalId) view returns (uint256)",
    "function hasVoted(uint256 proposalId, address account) view returns (bool)",
    "function castVote(uint256 proposalId, uint8 support) returns (uint256)",
    "function castVoteWithReason(uint256 proposalId, uint8 support, string reason) returns (uint256)",
    "function propose(address[] targets, uint256[] values, bytes[] calldatas, string description) returns (uint256)",
    "function queue(address[] targets, uint256[] values, bytes[] calldatas, bytes32 descriptionHash) returns (uint256)",
    "function execute(address[] targets, uint256[] values, bytes[] calldatas, bytes32 descriptionHash) payable returns (uint256)",
    "event ProposalCreated(uint256 proposalId, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 voteStart, uint256 voteEnd, string description)",
    "event VoteCast(address indexed voter, uint256 proposalId, uint8 support, uint256 weight, string reason)",
    "event ProposalExecuted(uint256 proposalId)",
    "event ProposalCanceled(uint256 proposalId)",
    "event ProposalQueued(uint256 proposalId, uint256 etaSeconds)",
];

// IGovernor.ProposalState enum, in order.
export const PROPOSAL_STATES = [
    "Pending",
    "Active",
    "Canceled",
    "Defeated",
    "Succeeded",
    "Queued",
    "Expired",
    "Executed",
];

// VoteType enum from GovernorCountingSimple.
export const VOTE_AGAINST = 0;
export const VOTE_FOR = 1;
export const VOTE_ABSTAIN = 2;
