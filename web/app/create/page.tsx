"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAccount } from "wagmi";
import { parseEventLogs } from "viem";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useSendTx } from "@/hooks/use-send-tx";
import { useContracts } from "@/hooks/use-contracts";
import { collectionFactoryAbi } from "@/lib/contracts/abis";
import { uploadFileToIpfs, uploadJsonToIpfs } from "@/lib/ipfs";

export default function CreatePage() {
  const { address } = useAccount();
  const { collectionFactory } = useContracts();
  const { send, isSigning, isConfirming, isConfirmed, receipt } = useSendTx();

  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [maxSupply, setMaxSupply] = useState("0");
  const [royaltyPercent, setRoyaltyPercent] = useState("5");
  const [description, setDescription] = useState("");
  const [bannerFile, setBannerFile] = useState<File | null>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [deployedAddress, setDeployedAddress] = useState<`0x${string}` | null>(null);

  const busy = isUploading || isSigning || isConfirming;

  // Once the transaction confirms, pull the freshly deployed collection's address
  // out of the CollectionCreated event rather than guessing at it.
  useEffect(() => {
    if (!isConfirmed || !receipt) return;
    const events = parseEventLogs({
      abi: collectionFactoryAbi,
      logs: receipt.logs,
      eventName: "CollectionCreated",
    });
    const created = events[0]?.args.collection;
    if (created) {
      setDeployedAddress(created);
      toast.success("Collection deployed.");
    }
  }, [isConfirmed, receipt]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!address) return toast.error("Connect your wallet first.");
    if (!collectionFactory) {
      return toast.error("The collection factory address isn't set for this network yet.");
    }
    if (!name.trim() || !symbol.trim()) return toast.error("Name and symbol are required.");

    const royaltyBps = Math.round(Number(royaltyPercent) * 100);
    if (Number.isNaN(royaltyBps) || royaltyBps < 0 || royaltyBps > 1000) {
      return toast.error("Royalty must be between 0% and 10%.");
    }

    let maxSupplyValue: bigint;
    try {
      maxSupplyValue = BigInt(maxSupply || "0");
    } catch {
      return toast.error("Max supply must be a whole number.");
    }

    try {
      setIsUploading(true);
      const imageUri = bannerFile ? await uploadFileToIpfs(bannerFile) : "";
      const contractUri = await uploadJsonToIpfs({ name, description, image: imageUri });
      setIsUploading(false);

      await send({
        address: collectionFactory,
        abi: collectionFactoryAbi,
        functionName: "createCollection",
        args: [name, symbol, maxSupplyValue, address, BigInt(royaltyBps), contractUri],
      });
    } catch {
      setIsUploading(false);
      // useSendTx already surfaced a toast for write errors; IPFS errors bubble up
      // from uploadFileToIpfs/uploadJsonToIpfs with their own message.
    }
  }

  if (deployedAddress) {
    return (
      <section className="mx-auto max-w-2xl px-4 py-24 sm:px-6 lg:px-8">
        <div className="rounded-2xl border border-border bg-abyss-raised p-10 text-center">
          <p className="font-mono text-xs uppercase tracking-wider text-base-blue">Deployed</p>
          <h1 className="mt-3 font-display text-2xl font-semibold">{name} is live</h1>
          <p className="mt-2 break-all font-mono text-xs text-mist">{deployedAddress}</p>
          <Button className="mt-6" asChild>
            <Link href={`/mint/${deployedAddress}`}>Mint into this collection</Link>
          </Button>
        </div>
      </section>
    );
  }

  return (
    <section className="mx-auto max-w-2xl px-4 py-16 sm:px-6 lg:px-8">
      <h1 className="font-display text-3xl font-semibold">Create a collection</h1>
      <p className="mt-2 text-sm text-mist">
        This deploys a new ERC-721 contract (as a low-cost clone) that you own and control.
      </p>

      <form onSubmit={handleSubmit} className="mt-10 flex flex-col gap-6">
        <div className="grid gap-6 sm:grid-cols-2">
          <div className="flex flex-col gap-2">
            <Label htmlFor="name">Name</Label>
            <Input id="name" value={name} onChange={(e) => setName(e.target.value)} placeholder="1wei Genesis" required />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="symbol">Symbol</Label>
            <Input id="symbol" value={symbol} onChange={(e) => setSymbol(e.target.value.toUpperCase())} placeholder="1WEI" required />
          </div>
        </div>

        <div className="flex flex-col gap-2">
          <Label htmlFor="description">Description</Label>
          <Textarea
            id="description"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="What is this collection about?"
          />
        </div>

        <div className="flex flex-col gap-2">
          <Label htmlFor="banner">Banner image</Label>
          <Input
            id="banner"
            type="file"
            accept="image/*"
            onChange={(e) => setBannerFile(e.target.files?.[0] ?? null)}
          />
        </div>

        <div className="grid gap-6 sm:grid-cols-2">
          <div className="flex flex-col gap-2">
            <Label htmlFor="maxSupply">Max supply</Label>
            <Input
              id="maxSupply"
              type="number"
              min={0}
              value={maxSupply}
              onChange={(e) => setMaxSupply(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">0 = uncapped</p>
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="royalty">Creator royalty (%)</Label>
            <Input
              id="royalty"
              type="number"
              min={0}
              max={10}
              step={0.1}
              value={royaltyPercent}
              onChange={(e) => setRoyaltyPercent(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">0–10%, paid to you on every resale</p>
          </div>
        </div>

        <Button type="submit" size="lg" disabled={busy || !address} className="mt-4">
          {isUploading
            ? "Uploading to IPFS…"
            : isSigning
              ? "Confirm in wallet…"
              : isConfirming
                ? "Deploying…"
                : "Create collection"}
        </Button>
        {!address && <p className="text-center text-sm text-muted-foreground">Connect your wallet to continue.</p>}
      </form>
    </section>
  );
}
