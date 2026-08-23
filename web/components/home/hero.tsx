import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { UnitLadder } from "./unit-ladder";

export function Hero() {
  return (
    <section className="mx-auto max-w-7xl px-4 pb-20 pt-16 sm:px-6 lg:px-8 lg:pt-24">
      <div className="grid gap-16 lg:grid-cols-2 lg:items-center">
        <div>
          <Badge variant="outline" className="mb-6">
            Built for Base
          </Badge>
          <h1 className="font-display text-4xl font-semibold leading-[1.05] tracking-tight sm:text-5xl lg:text-6xl">
            Start from <span className="text-base-blue">1</span>
            <span className="text-brass">wei</span>.
          </h1>
          <p className="mt-6 max-w-md text-lg text-mist">
            Every value on Ethereum is denominated down to its smallest unit. 1wei is a marketplace
            built on that same idea — list, bid, and collect NFTs on Base, priced to the last wei.
          </p>
          <div className="mt-9 flex flex-wrap gap-3">
            <Button size="lg" asChild>
              <Link href="/explore">Explore items</Link>
            </Button>
            <Button size="lg" variant="outline" asChild>
              <Link href="/create">Create a collection</Link>
            </Button>
          </div>
        </div>

        <div className="rounded-2xl border border-border bg-abyss-raised p-8">
          <p className="mb-6 font-mono text-xs uppercase tracking-wider text-muted-foreground">
            Ether, denominated
          </p>
          <UnitLadder />
        </div>
      </div>
    </section>
  );
}
