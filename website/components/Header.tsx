import Image from "next/image";
import Link from "next/link";
import { MobileNav } from "@/components/MobileNav";

const links = [
  { href: "/#features", label: "Features" },
  { href: "/#about", label: "About" },
  { href: "/#faq", label: "FAQ" }
];

export function Header() {
  return (
    <header className="sticky top-0 z-30 border-b border-[var(--border)] bg-[rgba(250,249,246,0.82)] backdrop-blur-md">
      <nav className="mx-auto flex max-w-6xl items-center justify-between px-5 py-3.5 sm:px-6">
        <Link className="focus-ring flex items-center gap-2.5" href="/" aria-label="Vicu home">
          <span className="flex h-9 w-9 items-center justify-center rounded-[11px] bg-[var(--surface-ink)] ring-1 ring-black/10">
            <Image src="/images/vicu-icon.png" alt="" width={24} height={24} className="h-6 w-6" priority />
          </span>
          <span className="text-[17px] font-semibold tracking-[-0.02em] text-[var(--ink)]">Vicu</span>
        </Link>

        <div className="hidden items-center gap-1 text-[15px] font-medium text-[var(--ink-soft)] md:flex">
          {links.map((link) => (
            <Link
              className="focus-ring rounded-lg px-3 py-2 transition-colors hover:text-[var(--ink)]"
              href={link.href}
              key={link.href}
            >
              {link.label}
            </Link>
          ))}
        </div>

        <Link
          className="focus-ring hidden rounded-full border border-[var(--border-strong)] bg-[var(--surface)] px-4 py-2 text-sm font-semibold text-[var(--ink)] transition-colors hover:border-[var(--brand-deep)] hover:bg-[var(--brand)] md:inline-flex"
          href="/#features"
        >
          Get the app
        </Link>

        <MobileNav links={links} />
      </nav>
    </header>
  );
}
