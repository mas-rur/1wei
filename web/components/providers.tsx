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
  ethereum: {
    createOnLogin: "users-without-wallets",
  },
},
        defaultChain: base,
        supportedChains: [base, baseSepolia],
      }}
    >
      <QueryClientProvider client={queryClient}>
        <WagmiProvider config={wagmiConfig}>{children}</WagmiProvider>
      </QueryClientProvider>
    </PrivyProvider>
  );
}
