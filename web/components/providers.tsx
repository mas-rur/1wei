"use client";

import type { ReactNode } from "react";
import { PrivyProvider } from "@privy-io/react-auth";
// Must come from @privy-io/wagmi, not plain `wagmi` — Privy's WagmiProvider keeps its
// embedded-wallet connector in sync with wagmi's account state.
import { WagmiProvider } from "@privy-io/wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { base, baseSepolia } from "viem/chains";
import { wagmiConfig } from "@/lib/wagmi";

const queryClient = new QueryClient();

export function Providers({ children }: { children: ReactNode }) {
  return (
    <PrivyProvider
      appId={process.env.NEXT_PUBLIC_PRIVY_APP_ID ?? ""}
      config={{
        // "wallet" surfaces MetaMask/Rabby/Coinbase Wallet/WalletConnect (any injected
        // provider plus WalletConnect) in one connect flow; email/google create an
        // embedded wallet on the spot — this is the whole "connect or create" flow
        // from a single button.
        loginMethods: ["wallet", "email", "google"],
        appearance: {
          theme: "dark",
          accentColor: "#0052FF",
        },
        embeddedWallets: {
          // Only spin up an embedded wallet for people who didn't bring one — someone
          // who connects MetaMask shouldn't also get an embedded wallet they never asked
          // for. Nested under `ethereum` since Privy configures this per chain type
          // (we don't touch `solana` — this app is Base/EVM-only).
          ethereum: {
            createOnLogin: "users-without-wallets",
          },
        },
        // Base Sepolia is the default for now — Phase 1's contracts are only deployed
        // there so far. Switch this to `base` once you deploy to mainnet (and fill in
        // the *_MAINNET address env vars in lib/contracts/addresses.ts).
        defaultChain: baseSepolia,
        supportedChains: [baseSepolia, base],
      }}
    >
      <QueryClientProvider client={queryClient}>
        <WagmiProvider config={wagmiConfig}>{children}</WagmiProvider>
      </QueryClientProvider>
    </PrivyProvider>
  );
}
