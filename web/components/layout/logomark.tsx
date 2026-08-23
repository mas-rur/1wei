import { cn } from "@/lib/utils";

export function Logomark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 20 20"
      fill="none"
      aria-hidden="true"
      className={cn("size-5", className)}
    >
      <path d="M6 2v16" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M6 5h3M6 8.5h5M6 12h3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" opacity="0.5" />
      <circle cx="6" cy="16" r="3" className="fill-brass" />
    </svg>
  );
}
