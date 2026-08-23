import { cn } from "@/lib/utils";

const rungs = [
  { label: "ether", exponent: "10¹⁸", width: 100 },
  { label: "milliether", exponent: "10¹⁵", width: 82 },
  { label: "microether", exponent: "10¹²", width: 64 },
  { label: "gwei", exponent: "10⁹", width: 46 },
  { label: "mwei", exponent: "10⁶", width: 30 },
  { label: "kwei", exponent: "10³", width: 16 },
  { label: "wei", exponent: "10⁰", width: 8 },
] as const;

/**
 * The Ethereum unit ladder, tapering from 1 ether down to 1 wei. Bar widths are a
 * stylized taper (not a literal log scale — the true range is 18 orders of
 * magnitude) chosen so the ladder reads clearly at a glance while still encoding
 * the real ordering of denominations. The "wei" rung is the one moment of brass
 * on the page: everything else in the UI is navy, frost, and Base blue.
 */
export function UnitLadder() {
  return (
    <div className="flex flex-col gap-2.5">
      {rungs.map((rung, i) => {
        const isWei = rung.label === "wei";
        return (
          <div
            key={rung.label}
            className="animate-rung-in flex items-center gap-3"
            style={{ animationDelay: `${i * 70}ms` }}
          >
            <span
              className={cn(
                "w-24 shrink-0 font-mono text-xs",
                isWei ? "font-medium text-brass" : "text-muted-foreground",
              )}
            >
              {rung.label}
            </span>
            <div className="h-1.5 flex-1 rounded-full bg-panel-muted">
              <div
                className={cn("h-full rounded-full", isWei ? "animate-wei-pulse bg-brass" : "bg-base-blue/70")}
                style={{ width: `${rung.width}%` }}
              />
            </div>
            <span className="w-12 shrink-0 text-right font-mono text-[11px] text-muted-foreground">
              {rung.exponent}
            </span>
          </div>
        );
      })}
    </div>
  );
}
