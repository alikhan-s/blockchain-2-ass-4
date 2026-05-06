// Minimal ABI for the GovernanceToken (ERC20Votes + ERC20Permit).
export const GOVERNANCE_TOKEN_ABI = [
    "function name() view returns (string)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
    "function totalSupply() view returns (uint256)",
    "function balanceOf(address account) view returns (uint256)",
    "function delegates(address account) view returns (address)",
    "function getVotes(address account) view returns (uint256)",
    "function getPastVotes(address account, uint256 timepoint) view returns (uint256)",
    "function delegate(address delegatee)",
    "function transfer(address to, uint256 amount) returns (bool)",
    "event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate)",
    "event DelegateVotesChanged(address indexed delegate, uint256 previousVotes, uint256 newVotes)",
];
