"use client";

import { useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { Menu, X } from "lucide-react";

type NavLink = { href: string; label: string };

export function MobileNav({ links }: { links: NavLink[] }) {
  const [open, setOpen] = useState(false);

  return (
    <Dialog.Root open={open} onOpenChange={setOpen}>
      <Dialog.Trigger asChild>
        <button
          type="button"
          aria-label="Open menu"
          className="focus-ring flex h-10 w-10 items-center justify-center rounded-full border border-[var(--border-strong)] bg-[var(--surface)] text-[var(--ink)] md:hidden"
        >
          <Menu size={19} aria-hidden="true" />
        </button>
      </Dialog.Trigger>

      <Dialog.Portal>
        <Dialog.Overlay className="animate-overlay-in fixed inset-0 z-40 bg-[rgba(23,25,28,0.45)] backdrop-blur-sm md:hidden" />
        <Dialog.Content className="animate-sheet-in fixed inset-x-3 top-3 z-50 rounded-2xl border border-[var(--border)] bg-[var(--surface)] p-4 shadow-[0_24px_60px_-20px_rgba(20,22,25,0.45)] md:hidden">
          <div className="flex items-center justify-between">
            <Dialog.Title className="text-[15px] font-semibold text-[var(--ink)]">Menu</Dialog.Title>
            <Dialog.Close asChild>
              <button
                type="button"
                aria-label="Close menu"
                className="focus-ring flex h-9 w-9 items-center justify-center rounded-full text-[var(--ink-soft)] transition-colors hover:bg-[var(--surface-muted)]"
              >
                <X size={18} aria-hidden="true" />
              </button>
            </Dialog.Close>
          </div>

          <nav className="mt-2 flex flex-col">
            {links.map((link) => (
              <Dialog.Close asChild key={link.href}>
                <a
                  href={link.href}
                  className="focus-ring rounded-xl px-3 py-3 text-[16px] font-medium text-[var(--ink)] transition-colors hover:bg-[var(--surface-muted)]"
                >
                  {link.label}
                </a>
              </Dialog.Close>
            ))}
          </nav>

          <Dialog.Close asChild>
            <a
              href="/#features"
              className="focus-ring mt-3 flex items-center justify-center rounded-full bg-[var(--brand)] px-5 py-3 text-[15px] font-semibold text-[var(--on-brand)]"
            >
              Get the app
            </a>
          </Dialog.Close>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
