"use client";

import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import type { Abi } from "viem";
import { toast } from "sonner";

/**
 * A deliberately simple, uniform shape for write calls — not derived from wagmi's
 * own (conditionally-typed, per-abi/functionName) parameter type. Extracting that
 * type via `Parameters<typeof writeContractAsync>[0]` outside of an actual call
 * expression breaks its generic inference (it collapses to the narrowest/default
 * case, e.g. `value` typed as `undefined`-only even for payable functions). Every
 * call site below already has its args hand-checked against lib/contracts/abis.ts,
 * so the tradeoff — losing per-function argument-shape checking here — is fine.
 */
interface SendTxConfig {
  address: `0x${string}`;
  abi: Abi;
  functionName: string;
  args?: readonly unknown[];
  value?: bigint;
}

/**
 * Thin wrapper around wagmi's write + wait-for-receipt hooks, shared by every
 * trading action (list, buy, bid, offer, etc.) so button states and error
 * toasts behave the same way everywhere.
 *
 * `receipt` (the full TransactionReceipt, once confirmed) is exposed so callers
 * can decode a specific event off `receipt.logs` with viem's `parseEventLogs` —
 * that's how we recover things like a newly created listingId or auctionId,
 * which the contract returns but a plain transaction hash doesn't carry.
 */
export function useSendTx() {
  const { writeContractAsync, isPending, data: hash, reset } = useWriteContract();
  const receiptQuery = useWaitForTransactionReceipt({ hash });

  async function send(config: SendTxConfig) {
    try {
      return await writeContractAsync(config as unknown as Parameters<typeof writeContractAsync>[0]);
    } catch (err) {
      const raw = err instanceof Error ? err.message : "Transaction failed";
      const message = raw.split("\n")[0].slice(0, 160);
      toast.error(message || "Transaction failed or was rejected.");
      throw err;
    }
  }

  return {
    send,
    hash,
    receipt: receiptQuery.data,
    isSigning: isPending,
    isConfirming: receiptQuery.isLoading,
    isConfirmed: receiptQuery.isSuccess,
    reset,
  };
}
