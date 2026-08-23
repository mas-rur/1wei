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
    // connections itself) drags in @coinbase/cdp-sdk, which conditionally imports a whole
    // family of per-chain payment sub-packages (@x402/evm, @x402/svm, @x402/core, ...) that
    // aren't installed as real dependencies. None of that code path is ever reached in this
    // app, so the whole package is stubbed out rather than chasing each sub-path individually.
    config.resolve.alias = {
      ...config.resolve.alias,
      "@coinbase/cdp-sdk": false,
    };
    return config;
  },
};

export default nextConfig;
