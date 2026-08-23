export const siteConfig = {
  name: "1wei",
  tagline: "Start from 1wei",
  description:
    "An NFT marketplace built for Base — fixed-price listings, English auctions, offers, and zero-gas lazy minting.",
  nav: [
    { label: "Explore", href: "/explore" },
    { label: "Create", href: "/create" },
  ] as const,
  links: {
    basescan: "https://basescan.org",
    basescanSepolia: "https://sepolia.basescan.org",
  },
};

export type SiteConfig = typeof siteConfig;
