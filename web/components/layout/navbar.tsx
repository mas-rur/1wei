"use client";

import Link from "next/link";
import { Menu, Search } from "lucide-react";
import { Logomark } from "./logomark";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";
import { ConnectButton } from "@/components/wallet/connect-button";
import { siteConfig } from "@/lib/site-config";

export function Navbar() {
  return (
    <header className="sticky top-0 z-40 border-b border-border bg-abyss/90 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-7xl items-center gap-4 px-4 sm:px-6 lg:px-8">
        <Link href="/" className="flex shrink-0 items-center gap-2 font-display text-lg font-semibold">
          <Logomark className="text-base-blue" />
          {siteConfig.name}
        </Link>

        <nav className="hidden items-center gap-1 md:flex">
          {siteConfig.nav.map((item) => (
            <Button key={item.href} variant="ghost" size="sm" asChild className="text-sm text-mist hover:text-foreground">
              <Link href={item.href}>{item.label}</Link>
            </Button>
          ))}
        </nav>

        <div className="relative ml-auto hidden max-w-md flex-1 md:block">
          <Search className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            type="search"
            placeholder="Search collections, items, and accounts"
            className="pl-11 font-mono text-xs placeholder:font-body placeholder:text-sm"
          />
        </div>

        <div className="ml-auto flex items-center gap-2 md:ml-0">
          <div className="hidden md:block">
            <ConnectButton />
          </div>

          <Sheet>
            <SheetTrigger asChild>
              <Button variant="ghost" size="icon" className="md:hidden">
                <Menu className="size-5" />
                <span className="sr-only">Open menu</span>
              </Button>
            </SheetTrigger>
            <SheetContent side="right" className="flex w-full flex-col gap-6 sm:max-w-xs">
              <SheetHeader>
                <SheetTitle className="flex items-center gap-2">
                  <Logomark className="text-base-blue" />
                  {siteConfig.name}
                </SheetTitle>
              </SheetHeader>

              <div className="relative">
                <Search className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                <Input type="search" placeholder="Search" className="pl-11" />
              </div>

              <nav className="flex flex-col gap-1">
                {siteConfig.nav.map((item) => (
                  <Link
                    key={item.href}
                    href={item.href}
                    className="rounded-lg px-3 py-2.5 text-base font-medium text-foreground hover:bg-secondary"
                  >
                    {item.label}
                  </Link>
                ))}
              </nav>

              <Separator />

              <ConnectButton />
            </SheetContent>
          </Sheet>
        </div>
      </div>
    </header>
  );
}
