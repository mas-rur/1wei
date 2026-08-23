const features = [
  {
    stat: "2.5%",
    title: "One flat platform fee",
    description: "No tiered pricing and no surprise deductions — every sale carries the same transparent cut.",
  },
  {
    stat: "0 gas",
    title: "Lazy minting",
    description: "List a full drop with zero upfront cost. Tokens mint the moment a buyer actually pays.",
  },
  {
    stat: "EIP-2981",
    title: "Creator royalties, enforced",
    description: "Royalties are checked and paid out by the marketplace contract on every sale, automatically.",
  },
  {
    stat: "Base L2",
    title: "Built for speed",
    description: "Ethereum-grade security with the block times and fees of a chain made to actually be used.",
  },
];

export function Features() {
  return (
    <section className="border-t border-border">
      <div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
        <div className="grid gap-px overflow-hidden rounded-2xl border border-border bg-border sm:grid-cols-2 lg:grid-cols-4">
          {features.map((feature) => (
            <div key={feature.title} className="bg-abyss p-6">
              <p className="font-mono text-sm font-medium text-base-blue">{feature.stat}</p>
              <h3 className="mt-3 font-display text-base font-semibold">{feature.title}</h3>
              <p className="mt-2 text-sm text-mist">{feature.description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
