"use client";

import { useEffect } from "react";
import { useReadContract } from "wagmi";
import { formatEther } from "viem";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { useSendTx } from "@/hooks/use-send-tx";
import { marketplaceAbi } from "@/lib/contracts/abis";

export function ListingPanel({
  marketplace,
  listingId,
  isSeller,
  onChanged,
}: {
  marketplace: `0x${string}`;
  listingId: bigint;
  isSeller: boolean;
  onChanged: () => void;
}) {
  const { data: listing, refetch } = useReadContract({
    address: marketplace,
    abi: marketplaceAbi,
    functionName: "listings",
    args: [listingId],
  });
  const { send, isSigning, isConfirming, isConfirmed } = useSendTx();

  useEffect(() => {
    if (isConfirmed) {
      refetch();
      onChanged();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isConfirmed]);

  if (!listing || !listing[6]) return null; // [6] = active
  const [, , , paymentToken, price, expiry] = listing;
  const isEth = paymentToken === "0x0000000000000000000000000000000000000000";
  const busy = isSigning || isConfirming;

  async function handleBuy() {
    try {
      await send({
        address: marketplace,
        abi: marketplaceAbi,
        functionName: "buy",
        args: [listingId],
        value: isEth ? price : undefined,
      });
    } catch {
      // toasted already
    }
  }

  async function handleCancel() {
    try {
      await send({ address: marketplace, abi: marketplaceAbi, functionName: "cancelListing", args: [listingId] });
    } catch {
      // toasted already
    }
  }

  return (
    <div className="flex flex-col gap-4 rounded-2xl border border-border bg-abyss-raised p-5">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs uppercase tracking-wider text-muted-foreground">Fixed price</p>
          <p className="mt-1 font-mono text-2xl font-semibold text-frost">
            {isEth ? `${formatEther(price)} ETH` : `${price.toString()} (ERC-20)`}
          </p>
        </div>
        <Badge variant="outline">Ends {new Date(Number(expiry) * 1000).toLocaleDateString()}</Badge>
      </div>
      {isSeller ? (
        <Button variant="outline" onClick={handleCancel} disabled={busy}>
          {busy ? "Cancelling…" : "Cancel listing"}
        </Button>
      ) : (
        <Button onClick={handleBuy} disabled={busy}>
          {isSigning ? "Confirm in wallet…" : isConfirming ? "Buying…" : "Buy now"}
        </Button>
      )}
    </div>
  );
}
