import Link from "next/link";
import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";

export default function AlpacaCallbackPage() {
  return (
    <div className="min-h-screen bg-[var(--background)]">
      <Header />
      <main className="mx-auto max-w-3xl px-5 py-16 sm:px-6">
        <div className="rounded-3xl border border-[var(--border)] bg-[var(--surface)] p-7 sm:p-9">
          <p className="text-[13px] font-semibold uppercase tracking-[0.18em] text-[var(--brand-amber)]">
            Alpaca Connect
          </p>
          <h1 className="mt-3 text-3xl font-semibold tracking-[-0.03em] text-[var(--ink)]">
            Authorization callback reserved
          </h1>
          <p className="mt-4 leading-8 text-[var(--ink-soft)]">
            This route is reserved for a future Alpaca Connect OAuth callback. The production
            implementation should validate the OAuth state, exchange the authorization code on a
            server-side endpoint, and return the user to the Vicu app.
          </p>
          <Link
            className="focus-ring mt-6 inline-flex rounded-full bg-[var(--brand)] px-5 py-3 text-sm font-semibold text-[var(--on-brand)]"
            href="/"
          >
            Return to Vicu
          </Link>
        </div>
      </main>
      <Footer />
    </div>
  );
}
