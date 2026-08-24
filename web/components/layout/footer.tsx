import Link from "next/link";
import { siteConfig } from "@/lib/site-config";

export function Footer() {
  return (
    <footer className="border-t border-border">
      <div className="mx-auto flex max-w-7xl flex-col gap-6 px-4 py-10 sm:flex-row sm:items-center sm:justify-between sm:px-6 lg:px-8">
        <div className="flex items-center gap-2 font-display text-sm font-medium text-mist">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt={siteConfig.name} className="h-4 w-auto" />
          <span>
            {siteConfig.name} <span className="text-muted-foreground">— {siteConfig.tagline}</span>
          </span>
        </div>

        <nav className="flex items-center gap-6 font-mono text-xs text-muted-foreground">
          {siteConfig.nav.map((item) => (
            <Link key={item.href} href={item.href} className="hover:text-foreground">
              {item.label}
            </Link>
          ))}
          <a
            href={siteConfig.links.basescan}
            target="_blank"
            rel="noreferrer"
            className="hover:text-foreground"
          >
            Basescan
          </a>
        </nav>
      </div>
    </footer>
  );
}
