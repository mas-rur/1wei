import { NextRequest, NextResponse } from "next/server";

export async function POST(request: NextRequest) {
  const jwt = process.env.PINATA_JWT;
  if (!jwt) {
    return NextResponse.json(
      { error: "Pinata isn't configured on the server (missing PINATA_JWT)." },
      { status: 500 },
    );
  }

  const incoming = await request.formData();
  const file = incoming.get("file");
  if (!(file instanceof File)) {
    return NextResponse.json({ error: "No file provided." }, { status: 400 });
  }

  const outgoing = new FormData();
  outgoing.append("file", file, file.name);

  const res = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
    method: "POST",
    headers: { Authorization: `Bearer ${jwt}` },
    body: outgoing,
  });

  if (!res.ok) {
    const text = await res.text();
    return NextResponse.json({ error: `Pinata upload failed: ${text}` }, { status: 502 });
  }

  const data = (await res.json()) as { IpfsHash: string };
  return NextResponse.json({ cid: data.IpfsHash, uri: `ipfs://${data.IpfsHash}` });
}
