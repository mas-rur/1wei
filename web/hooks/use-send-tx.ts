"use client";

import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { toast } from "sonner";

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

  async function send(config: Parameters<typeof writeContractAsync>[0]) {
    try {
      return await writeContractAsync(config);
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
