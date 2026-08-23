"use client";

import { usePrivy } from "@privy-io/react-auth";
import { useAccount } from "wagmi";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { AccountMenu } from "./account-menu";

export function ConnectButton() {
  const { ready, authenticated, login } = usePrivy();
  const { address } = useAccount();

  // Privy hasn't finished checking for an existing session yet — avoid a flash of the
  // "Connect" button for someone who's actually already logged in.
  if (!ready) {
    return <Skeleton className="h-10 w-32 rounded-full" />;
  }

  if (authenticated && address) {
    return <AccountMenu address={address} />;
  }

  return (
    <Button onClick={login} className="font-medium">
      Connect
    </Button>
  );
}
