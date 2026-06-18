import Link from "next/link";
import { ArrowRight } from "lucide-react";

export function BaseActions() {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
      <Link
        href="#features"
        className="focus-ring group inline-flex items-center justify-center gap-2 rounded-full bg-[var(--brand)] px-6 py-3.5 text-[15px] font-semibold text-[var(--on-brand)] shadow-[0_6px_20px_rgba(242,194,0,0.4)] transition-transform hover:-translate-y-0.5"
      >
        Explore the app
        <ArrowRight size={17} aria-hidden="true" className="transition-transform group-hover:translate-x-0.5" />
      </Link>
      <Link
        href="#about"
        className="focus-ring inline-flex items-center justify-center rounded-full border border-[var(--border-strong)] bg-[var(--surface)] px-6 py-3.5 text-[15px] font-semibold text-[var(--ink)] transition-colors hover:border-[var(--ink)]"
      >
        How it works
      </Link>
    </div>
  );
}
