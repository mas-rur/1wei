"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useParams } from "next/navigation";
import { useAccount, useReadContract } from "wagmi";
import { parseEventLogs } from "viem";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Skeleton } from "@/components/ui/skeleton";
import { useSendTx } from "@/hooks/use-send-tx";
import { nftCollectionAbi } from "@/lib/contracts/abis";
import { uploadFileToIpfs, uploadJsonToIpfs } from "@/lib/ipfs";

export default function MintPage() {
  const params = useParams<{ collection: string }>();
  const collection = params.collection as `0x${string}`;
  const { address } = useAccount();
  const { send, isSigning, isConfirming, isConfirmed, receipt } = useSendTx();

  const { data: collectionName } = useReadContract({
    address: collection,
    abi: nftCollectionAbi,
    functionName: "name",
  });
  const { data: owner, isLoading: isLoadingOwner } = useReadContract({
    address: collection,
    abi: nftCollectionAbi,
    functionName: "owner",
  });
  const { data: nextTokenId } = useReadContract({
    address: collection,
    abi: nftCollectionAbi,
    functionName: "nextTokenId",
  });

  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [imageFile, setImageFile] = useState<File | null>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [mintedTokenId, setMintedTokenId] = useState<bigint | null>(null);

  const isOwner = Boolean(address && owner && address.toLowerCase() === owner.toLowerCase());
  const busy = isUploading || isSigning || isConfirming;

  useEffect(() => {
    if (!isConfirmed || !receipt) return;
    const events = parseEventLogs({ abi: nftCollectionAbi, logs: receipt.logs, eventName: "Minted" });
    const tokenId = events[0]?.args.tokenId;
    if (tokenId !== undefined) {
      setMintedTokenId(tokenId);
      toast.success("Minted.");
    }
  }, [isConfirmed, receipt]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!address) return toast.error("Connect your wallet first.");
    if (!imageFile) return toast.error("Add an image.");
    if (!name.trim()) return toast.error("Name is required.");

    try {
      setIsUploading(true);
      const imageUri = await uploadFileToIpfs(imageFile);
      const tokenUri = await uploadJsonToIpfs({ name, description, image: imageUri });
      setIsUploading(false);

      await send({
        address: collection,
        abi: nftCollectionAbi,
        functionName: "mint",
        args: [address, tokenUri],
      });
    } catch {
      setIsUploading(false);
    }
  }

  if (isLoadingOwner) {
    return (
      <section className="mx-auto max-w-2xl px-4 py-16 sm:px-6 lg:px-8">
        <Skeleton className="h-64 w-full" />
      </section>
    );
  }

  if (mintedTokenId !== null) {
    return (
      <section className="mx-auto max-w-2xl px-4 py-24 sm:px-6 lg:px-8">
        <div className="rounded-2xl border border-border bg-abyss-raised p-10 text-center">
          <p className="font-mono text-xs uppercase tracking-wider text-base-blue">Minted</p>
          <h1 className="mt-3 font-display text-2xl font-semibold">{name}</h1>
          <p className="mt-2 font-mono text-xs text-mist">Token #{mintedTokenId.toString()}</p>
          <Button className="mt-6" asChild>
            <Link href={`/item/${collection}/${mintedTokenId.toString()}`}>View item</Link>
          </Button>
        </div>
      </section>
    );
  }

  return (
    <section className="mx-auto max-w-2xl px-4 py-16 sm:px-6 lg:px-8">
      <p className="font-mono text-xs uppercase tracking-wider text-base-blue">{collectionName ?? "Collection"}</p>
      <h1 className="mt-2 font-display text-3xl font-semibold">Mint an item</h1>
      {nextTokenId !== undefined && (
        <p className="mt-2 text-sm text-mist">This will be token #{nextTokenId.toString()}.</p>
      )}

      {!isOwner ? (
        <p className="mt-8 rounded-2xl border border-border bg-abyss-raised p-6 text-sm text-mist">
          Only this collection&apos;s owner can mint directly into it. Connect the wallet that created it, or ask the
          creator to mint for you.
        </p>
      ) : (
        <form onSubmit={handleSubmit} className="mt-10 flex flex-col gap-6">
          <div className="flex flex-col gap-2">
            <Label htmlFor="image">Image</Label>
            <Input id="image" type="file" accept="image/*" onChange={(e) => setImageFile(e.target.files?.[0] ?? null)} required />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="name">Name</Label>
            <Input id="name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Item #1" required />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="description">Description</Label>
            <Textarea id="description" value={description} onChange={(e) => setDescription(e.target.value)} />
          </div>

          <Button type="submit" size="lg" disabled={busy} className="mt-4">
            {isUploading ? "Uploading to IPFS…" : isSigning ? "Confirm in wallet…" : isConfirming ? "Minting…" : "Mint"}
          </Button>
        </form>
      )}
    </section>
  );
}
