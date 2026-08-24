"use client";

import { useEffect, useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { erc20Abi, formatEther, parseEther } from "viem";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Separator } from "@/components/ui/separator";
import { useSendTx } from "@/hooks/use-send-tx";
import { marketplaceAbi } from "@/lib/contracts/abis";
import { WETH_ADDRESS } from "@/lib/contracts/addresses";

const EXPIRY_SECONDS = 7 * 86_400; // offers default to a 7-day window

export function OfferPanel({
  nftContract,
  tokenId,
  marketplace,
  isOwner,
}: {
  nftContract: `0x${string}`;
  tokenId: bigint;
  marketplace: `0x${string}`;
  isOwner: boolean;
}) {
  const { address } = useAccount();
  const { send, isSigning, isConfirming, isConfirmed } = useSendTx();

  // --- Make an offer -----------------------------------------------------
  const [offerPrice, setOfferPrice] = useState("0.01");
  const busy = isSigning || isConfirming;

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: WETH_ADDRESS,
    abi: erc20Abi,
    functionName: "allowance",
    args: address ? [address, marketplace] : undefined,
    query: { enabled: Boolean(address) },
  });

  async function handleMakeOffer(e: React.FormEvent) {
    e.preventDefault();
    if (!address) return toast.error("Connect your wallet first.");
    let priceWei: bigint;
    try {
      priceWei = parseEther(offerPrice);
    } catch {
      return toast.error("Enter a valid WETH amount.");
    }

    try {
      if ((allowance ?? 0n) < priceWei) {
        await send({
          address: WETH_ADDRESS,
          abi: erc20Abi,
          functionName: "approve",
          args: [marketplace, priceWei],
        });
        await refetchAllowance();
      }
      const expiry = BigInt(Math.floor(Date.now() / 1000) + EXPIRY_SECONDS);
      await send({
        address: marketplace,
        abi: marketplaceAbi,
        functionName: "makeOffer",
        args: [nftContract, tokenId, priceWei, expiry],
      });
      toast.success("Offer submitted.");
    } catch {
      // toasted already
    }
  }

  // --- View / accept / cancel an offer by ID ------------------------------
  const [offerIdInput, setOfferIdInput] = useState("");
  const [lookupId, setLookupId] = useState<bigint | null>(null);

  const { data: offer, refetch: refetchOffer } = useReadContract({
    address: marketplace,
    abi: marketplaceAbi,
    functionName: "offers",
    args: lookupId !== null ? [lookupId] : undefined,
    query: { enabled: lookupId !== null },
  });

  useEffect(() => {
    if (isConfirmed) refetchOffer();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isConfirmed]);

  const [offerer, , , , offerPriceWei, , offerActive] = offer ?? [];
  const isOfferer = Boolean(address && offerer && address.toLowerCase() === offerer.toLowerCase());

  async function handleAcceptOffer() {
    if (lookupId === null) return;
    try {
      await send({ address: marketplace, abi: marketplaceAbi, functionName: "acceptOffer", args: [lookupId] });
    } catch {
      // toasted already
    }
  }

  async function handleCancelOffer() {
    if (lookupId === null) return;
    try {
      await send({ address: marketplace, abi: marketplaceAbi, functionName: "cancelOffer", args: [lookupId] });
    } catch {
      // toasted already
    }
  }

  return (
    <div className="flex flex-col gap-6 rounded-2xl border border-border bg-abyss-raised p-5">
      <div>
        <p className="text-sm font-medium text-frost">Make an offer</p>
        <p className="mt-1 text-xs text-muted-foreground">
          Offers are paid in WETH and don&apos;t require the item to be listed.
        </p>
        <form onSubmit={handleMakeOffer} className="mt-3 flex flex-col gap-2 sm:flex-row">
          <Input value={offerPrice} onChange={(e) => setOfferPrice(e.target.value)} inputMode="decimal" className="sm:flex-1" />
          <Button type="submit" disabled={busy}>
            {isSigning ? "Confirm in wallet…" : isConfirming ? "Submitting…" : "Make offer"}
          </Button>
        </form>
      </div>

      <Separator />

      <div>
        <p className="text-sm font-medium text-frost">View an offer</p>
        <p className="mt-1 text-xs text-muted-foreground">
          Paste an offer ID (from an OfferCreated event or the offerer) to review, accept, or cancel it.
        </p>
        <div className="mt-3 flex flex-col gap-2 sm:flex-row">
          <Label htmlFor="offer-id" className="sr-only">
            Offer ID
          </Label>
          <Input
            id="offer-id"
            value={offerIdInput}
            onChange={(e) => setOfferIdInput(e.target.value)}
            placeholder="Offer ID"
            className="sm:flex-1"
          />
          <Button
            type="button"
            variant="outline"
            onClick={() => setLookupId(offerIdInput ? BigInt(offerIdInput) : null)}
          >
            Look up
          </Button>
        </div>

        {offer && (
          <div className="mt-4 flex flex-col gap-3 rounded-xl border border-border bg-abyss p-4">
            <p className="font-mono text-lg font-semibold text-frost">
              {offerPriceWei !== undefined ? `${formatEther(offerPriceWei)} WETH` : "—"}
            </p>
            <p className="text-xs text-muted-foreground">{offerActive ? "Active" : "Not active"}</p>
            {offerActive && isOwner && (
              <Button onClick={handleAcceptOffer} disabled={busy}>
                {busy ? "Accepting…" : "Accept offer"}
              </Button>
            )}
            {offerActive && isOfferer && (
              <Button variant="outline" onClick={handleCancelOffer} disabled={busy}>
                {busy ? "Cancelling…" : "Cancel offer"}
              </Button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
