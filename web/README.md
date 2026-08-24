# 1wei — Frontend (Phases 2–3)

Project setup, wallet connection, navigation, and dark visual identity (Phase 2), plus the
full on-chain trading loop wired to Phase 1's contracts (Phase 3).

## 1. Setup

```bash
cd 1wei-web
npm install     # this sandbox has no network access, so this was NOT run for you
cp .env.local.example .env.local
```

Fill in `.env.local`:
- `NEXT_PUBLIC_PRIVY_APP_ID` — create a free app at [dashboard.privy.io](https://dashboard.privy.io).
- `NEXT_PUBLIC_MARKETPLACE_ADDRESS` / `NEXT_PUBLIC_COLLECTION_FACTORY_ADDRESS` — from
  deploying Phase 1's `script/Deploy.s.sol` to Base Sepolia. Nothing in Phase 3 works
  without these — the app defaults to Base Sepolia (see the version note in
  `components/providers.tsx`) since that's the only network Phase 1 is deployed to so far.
- `PINATA_JWT` — server-only (no `NEXT_PUBLIC_` prefix). Create one at pinata.cloud → API
  Keys. Used by `app/api/upload` and `app/api/upload-json` to pin images/metadata; never
  reaches the browser.

```bash
npm run dev
```

Add your own logo at `public/logo.png` — the navbar and footer both reference it directly
(`components/layout/navbar.tsx`, `footer.tsx`). No particular size is assumed; it renders at
a fixed height with natural aspect ratio.

---

## 2. Phase 3: the trading loop

Everything here talks to Phase 1's `Marketplace` and `CollectionFactory` contracts via wagmi
+ viem. No indexer yet (that's Phase 4) — every read is a direct, specific on-chain call.

**Create a collection** (`/create`) — uploads a banner image + JSON metadata to IPFS, then
calls `CollectionFactory.createCollection`. The deployed address is recovered from the
`CollectionCreated` event on the confirmed receipt (not guessed at) via viem's
`parseEventLogs`.

**Mint** (`/mint/[collection]`) — same IPFS upload pattern, then `NFTCollection.mint`. Gated
to the connected wallet being the collection's `owner()`. Lazy minting (the EIP-712 voucher
flow, `NFTCollection.redeem`) is **not** built yet — normal upfront-gas minting only for now.

**Trade an item** (`/item/[collection]/[tokenId]`) — reads `ownerOf`, `tokenURI`,
`activeListingId`, and `activeAuctionId`, then renders whichever applies:
- No listing/auction + you're the owner → choose fixed-price or auction, each gated behind
  a one-time `setApprovalForAll` if not already approved.
- Active listing → **Buy Now** (or **Cancel** if you're the seller).
- Active auction → **Place Bid** (enforcing the contract's minimum increment), **Settle**
  once ended (callable by anyone, matching the contract), or **Cancel** if you're the seller
  and no bids have landed yet.
- **Make an offer** is always available (WETH-denominated, approve-then-offer in one flow).
  Accepting/cancelling a *specific* offer works by pasting its ID — there's no "see all
  offers on this item" list yet, since that genuinely needs an indexer (Phase 4) to
  discover offer IDs without scanning every `OfferCreated` event yourself.

`/explore` (still a placeholder for the real filterable grid) got a manual
collection-address + token-ID lookup form in the meantime, so there's *some* way to reach
an item page without needing a link handed to you.

**Shared plumbing:**
- `lib/contracts/abis.ts` — hand-transcribed from the Phase 1 Solidity via viem's
  `parseAbi`. If you change and redeploy a contract, update the matching ABI here — nothing
  keeps these in sync automatically.
- `lib/contracts/addresses.ts` / `hooks/use-contracts.ts` — per-chain address lookup, keyed
  off whichever network the wallet is connected to.
- `hooks/use-send-tx.ts` — every write action goes through this: submits via wagmi's
  `useWriteContract`, tracks confirmation via `useWaitForTransactionReceipt`, toasts errors
  consistently. Exposes the full `receipt` so callers can decode a specific event
  (`CollectionCreated`, `Minted`, etc.) off its logs.
- `lib/ipfs.ts` + `app/api/upload*` — Pinata's classic REST endpoints
  (`pinFileToIPFS`/`pinJSONToIPFS`) called from server-side route handlers, so the JWT never
  ships to the browser. Deliberately not using Pinata's SDK package — one less dependency
  in a stack that's already proven fragile around version churn.

---

## 3. The wallet decision: Privy alone, not Privy + RainbowKit

The brief listed "wagmi v2 + viem + RainbowKit (or Dynamic/Privy for embedded wallets)" —
implying RainbowKit for external wallets and a separate embedded-wallet SDK bolted on
alongside it. I used **Privy by itself** instead: Privy's own connect modal already handles
*both* jobs — "wallet" as a login method surfaces MetaMask, Rabby, Coinbase Wallet, and
WalletConnect in one flow, and "email"/"google" create an embedded wallet on the spot.
Running RainbowKit next to it would mean two separate connect modals and two wallet-state
sources to keep in sync, for a solo-maintained project.

`@privy-io/wagmi`'s `WagmiProvider` (not the one from plain `wagmi`) is what keeps wagmi's
account state in sync with Privy's connectors — an easy one-letter-different import to get
wrong, so it's called out in comments everywhere it's used.

---

## 4. Design system

**Palette** — a deep navy (`#0A0E16`, not neutral black) grounds the page. Base's own brand
blue (`#0052FF`) is the *only* interactive accent. A muted brass (`#D4A537`) is reserved
exclusively for the "1 wei" marker in the hero unit ladder. All tokens live in
`app/globals.css`.

**Type** — Space Grotesk (display), IBM Plex Sans (body), IBM Plex Mono (anything numeric
or address-like — prices, token IDs, wallet addresses). Loaded via `next/font/google` in
`app/layout.tsx`.

**Signature element** — `components/home/unit-ladder.tsx`, the real Ethereum denomination
ladder tapering down to a highlighted "wei" rung. The one place motion happens on the page
beyond hover states.

Tailwind v4 is configured CSS-first (`app/globals.css`, no `tailwind.config.js`); shadcn's
primitives are hand-written in `components/ui/` against that token set. `npx shadcn@latest
add <component>` for anything new will match the existing `components.json`.

---

## 5. What's here

```
app/
  layout.tsx                       Root layout: fonts, metadata, Providers, Toaster, nav/footer
  page.tsx                         Home: Hero + Features
  globals.css                      Tailwind v4 theme
  create/page.tsx                  Create a collection
  mint/[collection]/page.tsx       Mint into a collection you own
  item/[collection]/[tokenId]/     Trade an item — list/buy/auction/bid/offer
  explore/page.tsx                 Placeholder + manual item lookup
  profile/page.tsx                 Placeholder, gated on connection
  api/upload/, api/upload-json/    Server-side Pinata pinning routes

components/
  providers.tsx                    Privy + wagmi + react-query
  wallet/, layout/, home/          Phase 2 pieces (connect button, nav, hero, etc.)
  trading/                         create-listing-form, create-auction-form, listing-panel,
                                    auction-panel, offer-panel
  ui/                               shadcn-style primitives (added: textarea, label, sonner)

lib/
  contracts/abis.ts, addresses.ts   ABIs + per-chain addresses
  wagmi.ts, site-config.ts, utils.ts
  ipfs.ts, metadata.ts              IPFS upload helpers + tokenURI metadata fetching

hooks/
  use-contracts.ts, use-send-tx.ts
```

---

## 6. What's deliberately not here yet

- **Lazy minting** — the EIP-712 voucher signing/redemption flow from Phase 1's
  `NFTCollection.redeem`. Needs its own design pass (how vouchers get stored/shared before
  redemption) rather than bolting it on here.
- **Offer discovery** — accepting/cancelling a known offer ID works; browsing "all offers on
  this item" needs an indexer. Phase 4.
- **Explore/Profile/Activity as real pages** — Phase 4, once indexing exists.
- **Light mode** — the CSS supports adding it, but it's out of scope by choice.

---

Ready for feedback before Phase 4 (Explore, Collection pages, Profile, Activity feed).
