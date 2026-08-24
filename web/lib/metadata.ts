import { ipfsToHttp } from "@/lib/ipfs";

export interface NftMetadata {
  name?: string;
  description?: string;
  image?: string;
}

export async function fetchMetadata(uri: string | undefined | null): Promise<NftMetadata | null> {
  if (!uri) return null;
  try {
    const res = await fetch(ipfsToHttp(uri));
    if (!res.ok) return null;
    return (await res.json()) as NftMetadata;
  } catch {
    return null;
  }
}
