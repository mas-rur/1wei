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
};

export default nextConfig;
