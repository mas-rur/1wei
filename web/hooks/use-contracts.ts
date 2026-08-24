"use client";

import { useChainId } from "wagmi";
import { contractAddressesByChain } from "@/lib/contracts/addresses";

export function useContracts() {
  const chainId = useChainId();
  return contractAddressesByChain[chainId] ?? {};
}
