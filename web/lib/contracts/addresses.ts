import { base, baseSepolia } from "viem/chains";

type ContractSet = {
  marketplace?: `0x${string}`;
  collectionFactory?: `0x${string}`;
};

/**
 * Base's WETH9 predeploy — identical address on Base mainnet and Base Sepolia.
 * This is also what Marketplace's immutable `WETH` is set to at deploy time
 * (see script/Deploy.s.sol in the contracts repo).
 */
export const WETH_ADDRESS: `0x${string}` = "0x4200000000000000000000000000000000000006";

export const contractAddressesByChain: Record<number, ContractSet> = {
  [baseSepolia.id]: {
    marketplace: process.env.NEXT_PUBLIC_MARKETPLACE_ADDRESS as `0x${string}` | undefined,
    collectionFactory: process.env.NEXT_PUBLIC_COLLECTION_FACTORY_ADDRESS as `0x${string}` | undefined,
  },
  [base.id]: {
    // Filled in once Phase 1's contracts are deployed to mainnet — separate env vars
    // so testnet and mainnet addresses don't collide.
    marketplace: process.env.NEXT_PUBLIC_MARKETPLACE_ADDRESS_MAINNET as `0x${string}` | undefined,
    collectionFactory: process.env.NEXT_PUBLIC_COLLECTION_FACTORY_ADDRESS_MAINNET as `0x${string}` | undefined,
  },
};
