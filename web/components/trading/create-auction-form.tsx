"use client";

import { useEffect, useState } from "react";
import { useAccount, useReadContract } from "wagmi";
import { parseEther } from "viem";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { useSendTx } from "@/hooks/use-send-tx";
import { nftCollectionAbi, marketplaceAbi } from "@/lib/contracts/abis";

const DURATIONS = [
  { label: "1 hour", seconds: 3_600 },
  { label: "6 hours", seconds: 21_600 },
  { label: "1 day", seconds: 86_400 },
  { label: "3 days", seconds: 259_200 },
  { label: "7 days", seconds: 604_800 },
];

export function CreateAuctionForm({
  nftContract,
  tokenId,
  marketplace,
  onCreated,
}: {
  nftContract: `0x${string}`;
  tokenId: bigint;
  marketplace: `0x${string}`;
  onCreated: () => void;
}) {
  const { address } = useAccount();
  const { send, isSigning, isConfirming, isConfirmed } = useSendTx();
  const [reserve, setReserve] = useState("0.01");
  const [duration, setDuration] = useState(DURATIONS[2].seconds);
  const [step, setStep] = useState<"idle" | "approving">("idle");

  const { data: isApproved, refetch: refetchApproval } = useReadContract({
    address: nftContract,
    abi: nftCollectionAbi,
    functionName: "isApprovedForAll",
    args: address ? [address, marketplace] : undefined,
    query: { enabled: Boolean(address) },
  });

  const busy = isSigning || isConfirming;

  useEffect(() => {
    if (isConfirmed) onCreated();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isConfirmed]);

  async function handleApprove() {
    setStep("approving");
    try {
      await send({
        address: nftContract,
        abi: nftCollectionAbi,
        functionName: "setApprovalForAll",
        args: [marketplace, true],
      });
      await refetchApproval();
      toast.success("Marketplace approved.");
    } finally {
      setStep("idle");
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    let reserveWei: bigint;
    try {
      reserveWei = parseEther(reserve);
    } catch {
      return toast.error("Enter a valid ETH reserve price.");
    }

    try {
      await send({
        address: marketplace,
        abi: marketplaceAbi,
        functionName: "createAuction",
        args: [nftContract, tokenId, reserveWei, BigInt(duration)],
      });
    } catch {
      // useSendTx already toasted
    }
  }

  if (!isApproved) {
    return (
      <div className="rounded-2xl border border-border bg-abyss-raised p-5">
        <p className="text-sm text-mist">
          Starting an auction requires a one-time approval — the item is held by the marketplace contract for the
          auction&apos;s duration, so bidders can trust it won&apos;t be moved.
        </p>
        <Button className="mt-4" onClick={handleApprove} disabled={busy}>
          {step === "approving" && busy ? "Approving…" : "Approve marketplace"}
        </Button>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-4 rounded-2xl border border-border bg-abyss-raised p-5">
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="flex flex-col gap-2">
          <Label htmlFor="reserve-price">Reserve price (ETH)</Label>
          <Input id="reserve-price" value={reserve} onChange={(e) => setReserve(e.target.value)} inputMode="decimal" />
        </div>
        <div className="flex flex-col gap-2">
          <Label htmlFor="auction-duration">Duration</Label>
          <select
            id="auction-duration"
            value={duration}
            onChange={(e) => setDuration(Number(e.target.value))}
            className="h-10 rounded-full border border-border bg-abyss px-4 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            {DURATIONS.map((d) => (
              <option key={d.seconds} value={d.seconds}>
                {d.label}
              </option>
            ))}
          </select>
        </div>
      </div>
      <Button type="submit" disabled={busy}>
        {isSigning ? "Confirm in wallet…" : isConfirming ? "Starting auction…" : "Start auction"}
      </Button>
    </form>
  );
}
