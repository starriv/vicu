import Image from "next/image";
import Link from "next/link";
import { siteConfig } from "@/lib/site";

export function Footer() {
  return (
    <footer className="border-t border-[var(--border)] bg-[var(--surface-muted)]">
      <div className="mx-auto grid max-w-6xl gap-8 px-5 py-12 sm:px-6 md:grid-cols-[1.6fr_1fr]">
        <div className="max-w-xl">
          <div className="flex items-center gap-2.5">
            <span className="flex h-8 w-8 items-center justify-center rounded-[10px] bg-[var(--surface-ink)] ring-1 ring-black/10">
              <Image src="/images/vicu-icon.png" alt="" width={20} height={20} className="h-5 w-5" />
            </span>
            <span className="text-[15px] font-semibold text-[var(--ink)]">Vicu</span>
          </div>
          <p className="mt-4 text-sm leading-7 text-[var(--ink-soft)]">
            Independent third-party iOS software for Alpaca brokerage account workflows. Vicu is not
            affiliated with or endorsed by Alpaca. Trading involves risk, including possible loss of
            principal.
          </p>
        </div>

        <div className="flex flex-col gap-3 text-sm font-medium text-[var(--ink-soft)] md:items-end">
          <Link className="focus-ring transition-colors hover:text-[var(--ink)]" href="/terms">
            Terms of Use
          </Link>
          <Link className="focus-ring transition-colors hover:text-[var(--ink)]" href="/privacy">
            Privacy Policy
          </Link>
          <a
            className="focus-ring transition-colors hover:text-[var(--ink)]"
            href={`mailto:${siteConfig.contactEmail}`}
          >
            {siteConfig.contactEmail}
          </a>
        </div>
      </div>
      <div className="border-t border-[var(--border)]">
        <p className="mx-auto max-w-6xl px-5 py-5 text-xs text-[var(--ink-mute)] sm:px-6">
          © {new Date().getFullYear()} Vicu. All rights reserved.
        </p>
      </div>
    </footer>
  );
}
