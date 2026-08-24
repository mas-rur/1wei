"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export default function ExplorePage() {
  const router = useRouter();
  const [collection, setCollection] = useState("");
  const [tokenId, setTokenId] = useState("");

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!collection.startsWith("0x") || !tokenId) return;
    router.push(`/item/${collection}/${tokenId}`);
  }

  return (
    <section className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
      <div className="mx-auto max-w-md rounded-2xl border border-border bg-abyss-raised p-8 text-center">
        <p className="font-mono text-xs uppercase tracking-wider text-base-blue">Phase 4</p>
        <h1 className="mt-3 font-display text-2xl font-semibold">Browsing is next</h1>
        <p className="mt-2 text-sm text-mist">
          A filterable grid of listings by price, collection, and status lands here once indexing is wired up. For
          now, look up a specific item directly:
        </p>

        <form onSubmit={handleSubmit} className="mt-6 flex flex-col gap-3 text-left">
          <div className="flex flex-col gap-2">
            <Label htmlFor="lookup-collection">Collection address</Label>
            <Input
              id="lookup-collection"
              value={collection}
              onChange={(e) => setCollection(e.target.value.trim())}
              placeholder="0x…"
              className="font-mono text-xs"
            />
          </div>
          <div className="flex flex-col gap-2">
            <Label htmlFor="lookup-token-id">Token ID</Label>
            <Input
              id="lookup-token-id"
              value={tokenId}
              onChange={(e) => setTokenId(e.target.value.trim())}
              placeholder="0"
              inputMode="numeric"
            />
          </div>
          <Button type="submit" className="mt-2">
            View item
          </Button>
        </form>
      </div>
    </section>
  );
}
