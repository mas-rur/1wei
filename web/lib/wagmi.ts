import { http } from "wagmi";
import { base, baseSepolia } from "viem/chains";
// Imported from @privy-io/wagmi rather than plain `wagmi` — this is required for the
// resulting config to work with <WagmiProvider> from @privy-io/wagmi (see providers.tsx).
import { createConfig } from "@privy-io/wagmi";

export const wagmiConfig = createConfig({
  chains: [base, baseSepolia],
  transports: {
    [base.id]: http(process.env.NEXT_PUBLIC_BASE_RPC_URL),
    [baseSepolia.id]: http(process.env.NEXT_PUBLIC_BASE_SEPOLIA_RPC_URL),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
