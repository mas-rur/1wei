import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  images: {
    // IPFS gateway + common NFT metadata hosts. Add more as collections need them —
    // Next/Image requires an explicit allowlist for remote hosts.
    remotePatterns: [
      { protocol: "https", hostname: "*.ipfs.w3s.link" },
      { protocol: "https", hostname: "ipfs.io" },
      { protocol: "https", hostname: "gateway.pinata.cloud" },
      { protocol: "https", hostname: "*.mypinata.cloud" },
    ],
  },
  webpack: (config) => {
    // wagmi's built-in Coinbase "Base Account" connector (pulled in transitively via
    // @privy-io/wagmi, which we don't configure or use directly — Privy manages wallet
    // connections itself) drags in @coinbase/cdp-sdk, which conditionally imports a
    // Solana-specific payment sub-package that isn't installed as a real dependency.
    // That code path is never reached in this app; stub it out so webpack's static
    // analysis doesn't fail the whole build over an unused optional feature.
    config.resolve.alias = {
      ...config.resolve.alias,
      "@x402/svm/exact/client": false,
    };
    return config;
  },
};

export default nextConfig;
