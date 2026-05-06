// Fill in after running the deployment script. The default values below are for
// `forge script` deploys to a local Anvil chain (chainId 31337).
export const CONTRACTS = {
    governanceToken: import.meta.env.VITE_GOVERNANCE_TOKEN ?? "0x0000000000000000000000000000000000000000",
    governor: import.meta.env.VITE_GOVERNOR ?? "0x0000000000000000000000000000000000000000",
    timelock: import.meta.env.VITE_TIMELOCK ?? "0x0000000000000000000000000000000000000000",
    treasury: import.meta.env.VITE_TREASURY ?? "0x0000000000000000000000000000000000000000",
    box: import.meta.env.VITE_BOX ?? "0x0000000000000000000000000000000000000000",
};

export const NETWORK = {
    expectedChainId: Number(import.meta.env.VITE_CHAIN_ID ?? 31337),
    chainName: import.meta.env.VITE_CHAIN_NAME ?? "Anvil Local",
    blockExplorer: import.meta.env.VITE_EXPLORER_URL ?? "",
};

// Approximate seconds-per-block on the deployed chain. Used for human-readable
// countdowns ("voting ends in ~3h"). Tweak per network.
export const BLOCK_TIME_SECONDS = Number(import.meta.env.VITE_BLOCK_TIME ?? 12);
