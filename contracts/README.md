# 1wei — Smart Contracts (Phase 1)

> "Start from 1wei" — an OpenSea-style NFT marketplace built for Base.

This is the Foundry project for **Phase 1** of 1wei: the on-chain layer. Three contracts:

| Contract | Purpose |
|---|---|
| `src/NFTCollection.sol` | ERC-721 collection logic (cloned per-collection by the factory) |
| `src/CollectionFactory.sol` | Deploys gas-cheap EIP-1167 clones of `NFTCollection` |
| `src/Marketplace.sol` | Fixed-price listings, English auctions, offers, fees, royalties |

---

## 1. Setup

```bash
# Install Foundry if you don't have it: https://book.getfoundry.sh/getting-started/installation
curl -L https://foundry.paradigm.xyz | bash
foundryup

cd 1wei-contracts
forge init --no-commit --force .   # skip if you're just unzipping this into a fresh folder

# Dependencies — this sandbox has no network access, so these were NOT run for you.
# Run them yourself once, from the project root:
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts@v5.6.1 --no-commit
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.6.1 --no-commit

cp .env.example .env   # then fill in PRIVATE_KEY / PLATFORM_FEE_RECIPIENT
```

`remappings.txt` is already set up to point `@openzeppelin/contracts/` and
`@openzeppelin/contracts-upgradeable/` at whatever you install into `lib/`.

### ⚠️ A version note that will save you a debugging session

OpenZeppelin Contracts **v5.5.0** removed `ReentrancyGuardUpgradeable` from the upgradeable
package (it's now "stateless" and lives only in the non-upgradeable `@openzeppelin/contracts`,
which doesn't pair cleanly with a clone/initializer pattern). If you've used OZ upgradeable
contracts before, you might reflexively reach for it — it's no longer there as of 5.5+.

`NFTCollection.sol` doesn't depend on it: the one function that needs reentrancy protection
(`redeem`, for lazy minting) rolls a two-line custom guard instead. If you bump OpenZeppelin
versions later, this is a dependency you'll never have to think about again. `Marketplace.sol`
and `CollectionFactory.sol` aren't clones, so they use the regular non-upgradeable
`ReentrancyGuard` normally — no issue there either way.

---

## 2. Architecture decisions worth knowing

**Why clones for collections?** `CollectionFactory` deploys one real `NFTCollection`
implementation, then every `createCollection()` call deploys an EIP-1167 minimal proxy
pointing at it — a few thousand gas instead of the ~2M+ gas of a full ERC-721 deployment.
Clones can't run constructors, so `NFTCollection` uses OpenZeppelin's upgradeable base
contracts purely for their `initialize()` pattern. There is no proxy admin and no upgrade
path — each clone's logic is permanently fixed to the implementation it was cloned from.

**Why is listing custody asymmetric?**
- **Fixed-price listings are non-custodial.** The seller keeps the NFT; the marketplace just
  needs an approval. Ownership and approval are re-checked at `buy()` time, so a stale listing
  (NFT sold/transferred elsewhere) just fails gracefully instead of allowing a bad sale.
- **Auctions are custodial.** The NFT moves into the marketplace contract when the auction is
  created. Bidders are locking up real capital for the auction's duration and need to trust the
  seller can't sell or move the asset elsewhere mid-auction — that guarantee is worth the extra
  transfer.
- **Offers are non-custodial and WETH-only.** No upfront escrow — the offerer's allowance is
  pulled at `acceptOffer()` time. This means one wallet can have many simultaneous open offers
  across different NFTs without locking capital in each one.

**Fee/royalty payout order:** on every sale, royalty → platform fee → seller, computed by
`_calculateFees`. The Marketplace enforces its own `MAX_ROYALTY_BPS` (10%) cap independent of
whatever a collection's `royaltyInfo()` reports — see `test_MarketplaceCapsExcessiveRoyalty` for
a live demonstration of why (a misconfigured or malicious NFT contract could otherwise claim an
unreasonable cut of every sale).

**ETH payouts never trap a sale.** `_sendETH` pushes ETH with a small gas stipend; if that push
fails (a royalty receiver or bidder whose contract reverts on receive, or is simply out of gas),
the amount is credited to `pendingWithdrawals` instead of reverting the whole
sale/settlement/refund. Affected accounts call `withdraw()` themselves. See
`test_PullPaymentFallbackOnFailedRefund`.

**Lazy minting** (`NFTCollection.redeem`) lets a creator sign an off-chain EIP-712
`LazyMintVoucher` (tokenId, URI, price, optional per-token royalty) with zero gas spent. A
buyer calls `redeem()` with the voucher and payment; the token is minted straight to them and
payment (minus the 2.5% platform fee) is forwarded to the creator. Great for dropping an entire
collection without paying to mint anything until it actually sells.

**Arbitrary NFT contracts are supported**, not just ones created via `CollectionFactory` — this
is meant to work like OpenSea, where anyone can list any ERC-721. `_calculateFees` wraps its
`ERC-165`/`ERC-2981` probes in `try/catch` so a single non-compliant collection can't brick
trading for itself.

---

## 3. Testing

```bash
forge test -vvv
forge coverage   # optional, needs the above deps installed
```

`test/` covers:
- `NFTCollection.t.sol` — minting, max supply, lazy-mint voucher verification (including replay
  and wrong-signer rejection), royalty caps.
- `CollectionFactory.t.sol` — clone deployment, storage independence between collections.
- `Marketplace.t.sol` — the full listing/auction/offer lifecycle, fee/royalty math, the
  pull-payment fallback, a live reentrancy attempt via a malicious bidder contract, and admin
  controls (pause, fee caps).

---

## 4. Deploying to Base Sepolia

Fill in `.env` (see `.env.example` — `WETH_ADDRESS` already defaults to Base's WETH9 predeploy,
`0x4200000000000000000000000000000000000006`, same address on Sepolia and mainnet), then:

```bash
source .env
forge script script/Deploy.s.sol:Deploy \
  --rpc-url base_sepolia \
  --broadcast \
  --verify
```

This deploys `CollectionFactory` and `Marketplace` and prints their addresses (plus the
`NFTCollection` implementation address the factory clones).

---

## 5. What's deliberately out of scope for Phase 1

- **ERC-1155** — you asked to prioritize ERC-721 first; the Marketplace's listing/auction/offer
  structs would need a `quantity` field to support semi-fungible items, which is a clean,
  additive change for a later phase.
- **Upgradeability of Marketplace/CollectionFactory themselves** — both are plain, non-upgradeable
  contracts. If you want a migration path later, the usual move is "deploy Marketplace v2, point
  the frontend at it" rather than a proxy, to avoid taking on upgrade-admin key risk this early.
- **Off-chain indexing** — Phase 1 emits the events (`ItemSold`, `BidPlaced`, `OfferAccepted`,
  etc.) an indexer needs, but wiring up Ponder/The Graph/Alchemy is Phase 2+ territory.

---

Ready for feedback before moving to Phase 2 (frontend foundation).
