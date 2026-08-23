"use client";

import { usePrivy } from "@privy-io/react-auth";
import { useAccount } from "wagmi";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

export default function ProfilePage() {
  const { ready, authenticated, login } = usePrivy();
  const { address } = useAccount();

  return (
    <section className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
      <div className="rounded-2xl border border-border bg-abyss-raised p-12 text-center">
        {!ready ? (
          <Skeleton className="mx-auto h-24 w-full max-w-sm" />
        ) : authenticated && address ? (
          <>
            <p className="font-mono text-xs uppercase tracking-wider text-base-blue">Phase 4</p>
            <h1 className="mt-3 font-display text-2xl font-semibold">Your profile is next</h1>
            <p className="mx-auto mt-2 max-w-sm text-sm text-mist">
              Owned items, listings, and activity for{" "}
              <span className="font-mono text-frost">
                {address.slice(0, 6)}…{address.slice(-4)}
              </span>{" "}
              land here once the trading UI is wired up.
            </p>
          </>
        ) : (
          <>
            <h1 className="font-display text-2xl font-semibold">Connect your wallet</h1>
            <p className="mx-auto mt-2 max-w-sm text-sm text-mist">
              Your owned items, listings, and offers will show up here once you&apos;re connected.
            </p>
            <Button className="mt-6" onClick={login}>
              Connect
            </Button>
          </>
        )}
      </div>
    </section>
  );
}
