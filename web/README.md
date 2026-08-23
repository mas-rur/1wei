# 1wei — Frontend (Phase 2)

Project setup, wallet connection (existing + embedded), navigation, and the dark visual
identity everything else builds on.

## 1. Setup

```bash
cd 1wei-web
npm install     # this sandbox has no network access, so this was NOT run for you
cp .env.local.example .env.local
```

Fill in `.env.local`:
- `NEXT_PUBLIC_PRIVY_APP_ID` — create a free app at [dashboard.privy.io](https://dashboard.privy.io).
  In the dashboard, set the allowed login methods (wallet, email, Google — matches the
  `loginMethods` in `components/providers.tsx`) and restrict supported chains to Base +
  Base Sepolia if you don't want Solana/other-chain options showing in the connect modal.
- `NEXT_PUBLIC_MARKETPLACE_ADDRESS` / `NEXT_PUBLIC_COLLECTION_FACTORY_ADDRESS` — leave
  blank for now; fill in once Phase 1's contracts are deployed. Phase 3 will read these.

```bash
npm run dev
```

### A version note

The brief asked for Next.js 15. Next.js 16 is the current stable release as of this
writing — the App Router fundamentals this project relies on haven't changed between the
two, so I've scaffolded against the latest 15.x line as specified rather than bumping the
major version without asking. `package.json` uses a `^15.4.0` range; swap it for `^16.0.0`
if you'd rather start on the newest release.

---

## 2. The wallet decision: Privy alone, not Privy + RainbowKit

The brief listed "wagmi v2 + viem + RainbowKit (or Dynamic/Privy for embedded wallets)" —
implying RainbowKit for external wallets and a separate embedded-wallet SDK bolted on
alongside it. I used **Privy by itself** instead, for one reason: Privy's own connect
modal already handles *both* jobs — "wallet" as a login method surfaces MetaMask, Rabby,
Coinbase Wallet, and WalletConnect in one flow, and "email"/"google" create an embedded
wallet on the spot. Running RainbowKit next to it would mean two separate connect modals
and two wallet-state sources to keep in sync, for a solo-maintained project. See
`components/providers.tsx` — one `loginMethods` array covers the whole brief.

`@privy-io/wagmi`'s `WagmiProvider` (not the one from plain `wagmi`) is what keeps wagmi's
account state in sync with Privy's connectors — `lib/wagmi.ts` and `components/providers.tsx`
both import from `@privy-io/wagmi` for this reason; it's an easy one-letter-different import
to get wrong.

`components/wallet/connect-button.tsx` and `account-menu.tsx` are the only two files that
know about Privy specifically (`usePrivy()` for `login`/`logout`/`authenticated`, wagmi's
own `useAccount`/`useBalance` for everything else) — swapping wallet providers later would
be contained to those two files plus `providers.tsx`.

---

## 3. Design system

**Palette** — a deep navy (`#0A0E16`, not neutral black) grounds the page. Base's own
brand blue (`#0052FF`) is the *only* interactive accent, used for buttons, links, and the
unit-ladder bars. A muted brass (`#D4A537`) is reserved exclusively for the "1 wei" marker
in the hero — it doesn't appear anywhere else in the interface, so it stays meaningful
instead of decorative. All tokens live in `app/globals.css`.

**Type** — Space Grotesk for display headings (a grotesk with enough engineered character
to suit a "precision denomination" brand without tipping into novelty), IBM Plex Sans for
body copy, IBM Plex Mono for anything numeric or address-like (prices, token IDs, wallet
addresses, the unit-ladder exponents). Loaded via `next/font/google` in `app/layout.tsx`.

**Signature element** — `components/home/unit-ladder.tsx`: the real Ethereum denomination
ladder (wei → kwei → mwei → gwei → microether → milliether → ether), bar width tapering
down to a highlighted, gently pulsing "wei" rung at the base. It's the literal shape of
"start from 1wei," not a generic stat block — and it's the only place motion happens on
the page beyond hover states, so it doesn't compete with itself.

Tailwind v4 is configured CSS-first (`app/globals.css` — no `tailwind.config.js`); shadcn's
usual primitives (Button, Input, Avatar, DropdownMenu, Sheet, Separator, Skeleton, Badge)
are hand-written in `components/ui/` against that same token set rather than pulled via the
CLI, since this sandbox can't reach npm. They're straightforward Radix + `cva` + `cn()` —
running `npx shadcn@latest add <component>` later for anything new will match the existing
`components.json` config.

---

## 4. What's here

```
app/
  layout.tsx          Root layout: fonts, metadata, Providers, Navbar/Footer shell
  page.tsx             Home: Hero + Features
  globals.css          Tailwind v4 theme — palette, fonts, hero keyframes
  explore/, create/,   Placeholder pages so nav links resolve — built out in
  profile/page.tsx     Phase 3 (create) and Phase 4 (explore, profile)

components/
  providers.tsx        Privy + wagmi + react-query provider tree
  wallet/              connect-button.tsx, account-menu.tsx
  layout/              navbar.tsx, footer.tsx, logomark.tsx
  home/                hero.tsx, features.tsx, unit-ladder.tsx
  ui/                  Hand-written shadcn-style primitives

lib/
  wagmi.ts             wagmi config (Base + Base Sepolia) via @privy-io/wagmi
  site-config.ts        Nav links, site metadata, external links
  utils.ts             cn() helper
```

---

## 5. What's deliberately not here yet

- **Contract reads/writes** — `lib/wagmi.ts` is configured for Base + Base Sepolia, but no
  component calls the Marketplace or CollectionFactory yet. That's Phase 3.
- **Real data on Explore/Profile** — both are placeholders gated appropriately (Profile
  already checks connection status live; Explore doesn't need to yet).
- **Light mode** — the CSS is structured so it wouldn't be hard to add
  (`@custom-variant dark` is already in place), but the brief asked for a dark UI and a
  toggle is one more thing for a solo dev to maintain, so it's out for now.

---

Ready for feedback before moving to Phase 3 (Core Trading UI: mint, list, auction, offer, buy).
