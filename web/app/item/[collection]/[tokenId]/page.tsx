"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { useAccount, useReadContract } from "wagmi";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { useContracts } from "@/hooks/use-contracts";
import { nftCollectionAbi, marketplaceAbi } from "@/lib/contracts/abis";
import { ipfsToHttp } from "@/lib/ipfs";
import { fetchMetadata, type NftMetadata } from "@/lib/metadata";
import { ListingPanel } from "@/components/trading/listing-panel";
import { AuctionPanel } from "@/components/trading/auction-panel";
import { CreateListingForm } from "@/components/trading/create-listing-form";
import { CreateAuctionForm } from "@/components/trading/create-auction-form";
import { OfferPanel } from "@/components/trading/offer-panel";

export default function ItemPage() {
  const params = useParams<{ collection: string; tokenId: string }>();
  const nftContract = params.collection as `0x${string}`;
  const parsedTokenId = (() => {
    try {
      return BigInt(params.tokenId);
    } catch {
      return null;
    }
  })();
  const tokenId = parsedTokenId ?? 0n;

  const { address } = useAccount();
  const { marketplace } = useContracts();
  const [metadata, setMetadata] = useState<NftMetadata | null>(null);
  const [sellAction, setSellAction] = useState<"list" | "auction" | null>(null);

  const { data: owner, isLoading: isLoadingOwner } = useReadContract({
    address: nftContract,
    abi: nftCollectionAbi,
    functionName: "ownerOf",
    args: [tokenId],
  });
  const { data: tokenUri } = useReadContract({
    address: nftContract,
    abi: nftCollectionAbi,
    functionName: "tokenURI",
    args: [tokenId],
  });
  const { data: collectionName } = useReadContract({
    address: nftContract,
    abi: nftCollectionAbi,
    functionName: "name",
  });

  const listingQuery = useReadContract({
    address: marketplace,
    abi: marketplaceAbi,
    functionName: "activeListingId",
    args: [nftContract, tokenId],
    query: { enabled: Boolean(marketplace) },
  });
  const auctionQuery = useReadContract({
    address: marketplace,
    abi: marketplaceAbi,
    functionName: "activeAuctionId",
    args: [nftContract, tokenId],
    query: { enabled: Boolean(marketplace) },
  });

  useEffect(() => {
    if (!tokenUri) return;
    fetchMetadata(tokenUri).then(setMetadata);
  }, [tokenUri]);

  const isOwner = Boolean(address && owner && address.toLowerCase() === owner.toLowerCase());
  const hasListing = Boolean(listingQuery.data && listingQuery.data > 0n);
  const hasAuction = Boolean(auctionQuery.data && auctionQuery.data > 0n);

  function refreshMarketState() {
    listingQuery.refetch();
    auctionQuery.refetch();
    setSellAction(null);
  }

  if (parsedTokenId === null) {
    return (
      <section className="mx-auto max-w-2xl px-4 py-24 text-center sm:px-6 lg:px-8">
        <p className="text-sm text-mist">That doesn&apos;t look like a valid token ID.</p>
      </section>
    );
  }

  if (isLoadingOwner) {
    return (
      <section className="mx-auto max-w-5xl px-4 py-16 sm:px-6 lg:px-8">
        <Skeleton className="h-96 w-full" />
      </section>
    );
  }

  if (!marketplace) {
    return (
      <section className="mx-auto max-w-2xl px-4 py-24 text-center sm:px-6 lg:px-8">
        <p className="text-sm text-mist">
          The marketplace address isn&apos;t configured for this network yet — nothing to trade against.
        </p>
      </section>
    );
  }

  return (
    <section className="mx-auto max-w-5xl px-4 py-12 sm:px-6 lg:px-8">
      <div className="grid gap-10 lg:grid-cols-2">
        <div className="overflow-hidden rounded-2xl border border-border bg-abyss-raised">
          {metadata?.image ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={ipfsToHttp(metadata.image)} alt={metadata.name ?? "NFT"} className="aspect-square w-full object-cover" />
          ) : (
            <div className="aspect-square w-full bg-panel-muted" />
          )}
        </div>

        <div className="flex flex-col gap-6">
          <div>
            <p className="font-mono text-xs uppercase tracking-wider text-base-blue">
              {collectionName ?? "Collection"}
            </p>
            <h1 className="mt-2 font-display text-3xl font-semibold">{metadata?.name ?? `Token #${tokenId}`}</h1>
            {metadata?.description && <p className="mt-3 text-sm text-mist">{metadata.description}</p>}
            {owner && (
              <Badge variant="outline" className="mt-4">
                Owned by {isOwner ? "you" : `${owner.slice(0, 6)}…${owner.slice(-4)}`}
              </Badge>
            )}
          </div>

          {hasListing && listingQuery.data && (
            <ListingPanel
              marketplace={marketplace}
              listingId={listingQuery.data}
              isSeller={isOwner}
              onChanged={refreshMarketState}
            />
          )}

          {hasAuction && auctionQuery.data && (
            <AuctionPanel
              marketplace={marketplace}
              auctionId={auctionQuery.data}
              isSeller={isOwner}
              onChanged={refreshMarketState}
            />
          )}

          {isOwner && !hasListing && !hasAuction && (
            <div className="flex flex-col gap-3">
              <div className="flex gap-2">
                <button
                  onClick={() => setSellAction("list")}
                  className={`flex-1 rounded-full border px-4 py-2 text-sm font-medium transition-colors ${
                    sellAction === "list" ? "border-base-blue bg-base-blue/10 text-frost" : "border-border text-mist"
                  }`}
                >
                  Fixed price
                </button>
                <button
                  onClick={() => setSellAction("auction")}
                  className={`flex-1 rounded-full border px-4 py-2 text-sm font-medium transition-colors ${
                    sellAction === "auction" ? "border-base-blue bg-base-blue/10 text-frost" : "border-border text-mist"
                  }`}
                >
                  Auction
                </button>
              </div>
              {sellAction === "list" && (
                <CreateListingForm
                  nftContract={nftContract}
                  tokenId={tokenId}
                  marketplace={marketplace}
                  onCreated={refreshMarketState}
                />
              )}
              {sellAction === "auction" && (
                <CreateAuctionForm
                  nftContract={nftContract}
                  tokenId={tokenId}
                  marketplace={marketplace}
                  onCreated={refreshMarketState}
                />
              )}
            </div>
          )}

          {!hasAuction && <OfferPanel nftContract={nftContract} tokenId={tokenId} marketplace={marketplace} isOwner={isOwner} />}
        </div>
      </div>
    </section>
  );
}
