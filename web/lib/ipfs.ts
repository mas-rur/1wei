async function parseUploadResponse(res: Response): Promise<string> {
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data?.error ?? "Upload failed.");
  }
  return data.uri as string;
}

export async function uploadFileToIpfs(file: File): Promise<string> {
  const formData = new FormData();
  formData.append("file", file);
  const res = await fetch("/api/upload", { method: "POST", body: formData });
  return parseUploadResponse(res);
}

export async function uploadJsonToIpfs(json: unknown): Promise<string> {
  const res = await fetch("/api/upload-json", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(json),
  });
  return parseUploadResponse(res);
}

/** Converts an `ipfs://<cid>/...` URI to an HTTP(S) URL via a public gateway. */
export function ipfsToHttp(uri: string | undefined | null): string {
  if (!uri) return "";
  if (!uri.startsWith("ipfs://")) return uri;
  const path = uri.replace("ipfs://", "");
  const gateway = process.env.NEXT_PUBLIC_IPFS_GATEWAY ?? "https://gateway.pinata.cloud/ipfs";
  return `${gateway}/${path}`;
}
