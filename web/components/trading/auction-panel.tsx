"use client";

import { useEffect, useState } from "react";
import { useReadContract } from "wagmi";
import { formatEther, parseEther, zeroAddress } from "viem";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { useSendTx } from "@/hooks/use-send-tx";
import { marketplaceAbi } from "@/lib/contracts/abis";

export function AuctionPanel({
  marketplace,
  auctionId,
  isSeller,
  onChanged,
}: {
  marketplace: `0x${string}`;
  auctionId: bigint;
  isSeller: boolean;
  onChanged: () => void;
}) {
  const { data: auction, refetch } = useReadContract({
    address: marketplace,
    abi: marketplaceAbi,
    functionName: "auctions",
    args: [auctionId],
  });
  const { data: minIncrementBps } = useReadContract({
    address: marketplace,
    abi: marketplaceAbi,
    functionName: "MIN_BID_INCREMENT_BPS",
  });
  const { send, isSigning, isConfirming, isConfirmed } = useSendTx();
  const [bidAmount, setBidAmount] = useState("");

  useEffect(() => {
    if (isConfirmed) {
      refetch();
      onChanged();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isConfirmed]);

  if (!auction || !auction[7]) return null; // [7] = active
  const [, , , reservePrice, highestBid, highestBidder, endTime, , settled] = auction;
  const hasEnded = Date.now() >= Number(endTime) * 1000;
  const hasBids = highestBidder !== zeroAddress;
  const busy = isSigning || isConfirming;

  const minBid = hasBids
    ? highestBid + (highestBid * (minIncrementBps ?? 500n)) / 10_000n
    : reservePrice === 0n
      ? 1n
      : reservePrice;

  async function handleBid(e: React.FormEvent) {
    e.preventDefault();
    let value: bigint;
    try {
      value = parseEther(bidAmount);
    } catch {
      return;
    }
    try {
      await send({ address: marketplace, abi: marketplaceAbi, functionName: "placeBid", args: [auctionId], value });
      setBidAmount("");
    } catch {
      // toasted already
    }
  }

  async function handleSettle() {
    try {
      await send({ address: marketplace, abi: marketplaceAbi, functionName: "settleAuction", args: [auctionId] });
    } catch {
      // toasted already
    }
  }

  async function handleCancel() {
    try {
      await send({ address: marketplace, abi: marketplaceAbi, functionName: "cancelAuction", args: [auctionId] });
    } catch {
      // toasted already
    }
  }

  return (
    <div className="flex flex-col gap-4 rounded-2xl border border-border bg-abyss-raised p-5">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-xs uppercase tracking-wider text-muted-foreground">
            {hasBids ? "Highest bid" : "Reserve price"}
          </p>
          <p className="mt-1 font-mono text-2xl font-semibold text-frost">
            {formatEther(hasBids ? highestBid : reservePrice)} ETH
          </p>
        </div>
        <Badge variant={hasEnded ? "secondary" : "outline"}>
          {hasEnded ? "Ended" : `Ends ${new Date(Number(endTime) * 1000).toLocaleString()}`}
        </Badge>
      </div>

      {!settled && hasEnded && (
        <Button onClick={handleSettle} disabled={busy}>
          {busy ? "Settling…" : "Settle auction"}
        </Button>
      )}

      {!hasEnded && isSeller && !hasBids && (
        <Button variant="outline" onClick={handleCancel} disabled={busy}>
          {busy ? "Cancelling…" : "Cancel auction"}
        </Button>
      )}

      {!hasEnded && !isSeller && (
        <form onSubmit={handleBid} className="flex flex-col gap-2">
          <Input
            value={bidAmount}
            onChange={(e) => setBidAmount(e.target.value)}
            placeholder={`Min ${formatEther(minBid)} ETH`}
            inputMode="decimal"
          />
          <Button type="submit" disabled={busy}>
            {isSigning ? "Confirm in wallet…" : isConfirming ? "Placing bid…" : "Place bid"}
          </Button>
        </form>
      )}
    </div>
  );
}
