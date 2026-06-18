import type { ReactNode } from "react";
import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";
import { siteConfig } from "@/lib/site";

export function LegalPage({
  title,
  intro,
  children
}: {
  title: string;
  intro: string;
  children: ReactNode;
}) {
  return (
    <div className="min-h-screen bg-[var(--background)]">
      <Header />
      <main className="mx-auto max-w-4xl px-5 py-12 sm:px-6 sm:py-16">
        <div className="mb-9 border-b border-[var(--border)] pb-8">
          <p className="text-[13px] font-semibold uppercase tracking-[0.18em] text-[var(--brand-amber)]">
            {siteConfig.name}
          </p>
          <h1 className="mt-3 text-4xl font-semibold leading-tight tracking-[-0.03em] text-[var(--ink)] sm:text-5xl">
            {title}
          </h1>
          <p className="mt-4 max-w-3xl text-lg leading-8 text-[var(--ink-soft)]">{intro}</p>
          <p className="mt-4 text-sm font-medium text-[var(--ink-mute)]">
            Last updated: {siteConfig.lastUpdated}
          </p>
        </div>
        <article className="legal-copy">{children}</article>
      </main>
      <Footer />
    </div>
  );
}
