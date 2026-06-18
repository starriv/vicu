import Image from "next/image";
import { KeyRound, LineChart, ShieldCheck, Smartphone } from "lucide-react";
import { BaseActions } from "@/components/BaseActions";
import { Faq } from "@/components/Faq";
import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";
import { appHighlights, complianceNotes } from "@/lib/site";

const secondaryFeatures = [
  {
    title: "Market context",
    body: "Search symbols, read quotes and news, and check charts before you place an order.",
    icon: LineChart
  },
  {
    title: "Your connection",
    body: "You connect your own Alpaca account and stay in control — revoke access anytime.",
    icon: KeyRound
  },
  {
    title: "Native iOS",
    body: "A SwiftUI client with credentials kept in the device Keychain in the current release.",
    icon: Smartphone
  }
];

export default function Home() {
  return (
    <div className="min-h-screen">
      <Header />
      <main>
        {/* Hero */}
        <section className="relative overflow-hidden border-b border-[var(--border)]">
          <div className="dotgrid pointer-events-none absolute inset-0 opacity-70" aria-hidden="true" />
          <div
            className="pointer-events-none absolute -right-32 -top-40 h-[520px] w-[520px] rounded-full bg-[var(--brand)] opacity-25 blur-[120px]"
            aria-hidden="true"
          />
          <div className="relative mx-auto grid max-w-6xl items-center gap-12 px-5 pb-20 pt-14 sm:px-6 lg:grid-cols-[1.02fr_0.98fr] lg:pb-24 lg:pt-20">
            <div>
              <div className="inline-flex items-center gap-2 rounded-full border border-[var(--border-strong)] bg-[var(--surface)] px-3.5 py-1.5 text-[13px] font-semibold text-[var(--ink-soft)]">
                <ShieldCheck size={15} className="text-[var(--brand-amber)]" aria-hidden="true" />
                Independent client for Alpaca accounts
              </div>
              <h1 className="mt-6 text-[2.9rem] font-semibold leading-[1.02] tracking-[-0.035em] text-[var(--ink)] sm:text-6xl">
                Your Alpaca account,
                <br />
                <span className="relative inline-block">
                  <span className="relative z-10">in your pocket.</span>
                  <span
                    className="absolute inset-x-[-2px] bottom-1.5 -z-0 h-3.5 rounded bg-[var(--brand)] sm:bottom-2 sm:h-4"
                    aria-hidden="true"
                  />
                </span>
              </h1>
              <p className="mt-6 max-w-xl text-lg leading-8 text-[var(--ink-soft)]">
                Vicu is a focused iOS app for monitoring your portfolio, researching the market, and
                placing orders — built for people who already trade on Alpaca.
              </p>
              <div className="mt-8">
                <BaseActions />
              </div>
              <p className="mt-7 max-w-md text-[13px] leading-6 text-[var(--ink-mute)]">
                Vicu is not affiliated with or endorsed by Alpaca. Trading involves risk, including
                possible loss of principal.
              </p>
            </div>

            <div className="relative mx-auto flex w-full max-w-md items-center justify-center lg:max-w-none">
              <Image
                src="/images/screenshots/markets-dark.png"
                alt="Vicu market overview screen"
                width={348}
                height={757}
                className="w-[58%] translate-y-6 rotate-[-5deg] rounded-[26px] shadow-[0_30px_60px_-20px_rgba(20,22,25,0.45)]"
              />
              <Image
                src="/images/screenshots/home-light.png"
                alt="Vicu account overview screen"
                width={348}
                height={757}
                priority
                className="-ml-12 w-[62%] translate-y-[-8px] rotate-[3deg] rounded-[26px] shadow-[0_30px_70px_-18px_rgba(20,22,25,0.5)] ring-1 ring-black/5"
              />
            </div>
          </div>
        </section>

        {/* Features */}
        <section id="features" className="mx-auto max-w-6xl px-5 py-20 sm:px-6 sm:py-24">
          <div className="max-w-2xl">
            <p className="text-[13px] font-semibold uppercase tracking-[0.18em] text-[var(--brand-amber)]">
              What it does
            </p>
            <h2 className="mt-3 text-3xl font-semibold leading-tight tracking-[-0.03em] text-[var(--ink)] sm:text-4xl">
              Everything you need to stay on top of your account.
            </h2>
          </div>

          <div className="mt-12 grid gap-5 lg:grid-cols-12">
            {/* Large account tile */}
            <article className="group relative overflow-hidden rounded-3xl border border-[var(--border)] bg-[var(--surface)] p-7 sm:p-9 lg:col-span-7">
              <div className="max-w-md">
                <h3 className="text-2xl font-semibold tracking-[-0.02em] text-[var(--ink)]">
                  See your whole account at a glance
                </h3>
                <p className="mt-3 text-[15px] leading-7 text-[var(--ink-soft)]">
                  Portfolio value, cash, buying power, positions, and account activity — organized for
                  a fast daily check-in, with charts across every time range.
                </p>
              </div>
              <div className="relative mt-8 flex justify-center overflow-hidden">
                <Image
                  src="/images/screenshots/home-light.png"
                  alt="Vicu account home screen with portfolio value and balances"
                  width={348}
                  height={757}
                  className="w-[72%] max-w-[300px] translate-y-6 rounded-t-[26px] shadow-[0_24px_50px_-20px_rgba(20,22,25,0.4)] ring-1 ring-black/5 transition-transform duration-500 group-hover:-translate-y-0"
                />
              </div>
            </article>

            {/* Trade tile */}
            <article className="group relative overflow-hidden rounded-3xl border border-[var(--border)] bg-[var(--surface-ink)] p-7 sm:p-9 lg:col-span-5">
              <div className="max-w-xs">
                <h3 className="text-2xl font-semibold tracking-[-0.02em] text-white">
                  Order entry, built for speed
                </h3>
                <p className="mt-3 text-[15px] leading-7 text-white/65">
                  A clean order ticket for shares or notional amounts, with buying power always in
                  view before you submit.
                </p>
              </div>
              <div className="relative mt-8 flex justify-center">
                <Image
                  src="/images/screenshots/trade-dark.png"
                  alt="Vicu order entry screen"
                  width={348}
                  height={757}
                  className="w-[68%] max-w-[260px] translate-y-6 rounded-t-[26px] shadow-[0_24px_50px_-16px_rgba(0,0,0,0.6)] transition-transform duration-500 group-hover:-translate-y-0"
                />
              </div>
            </article>

            {/* Three compact tiles */}
            {secondaryFeatures.map((item) => {
              const Icon = item.icon;
              return (
                <article
                  className="rounded-3xl border border-[var(--border)] bg-[var(--surface)] p-7 lg:col-span-4"
                  key={item.title}
                >
                  <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-[var(--brand)] text-[var(--on-brand)]">
                    <Icon size={20} aria-hidden="true" />
                  </div>
                  <h3 className="mt-5 text-lg font-semibold tracking-[-0.01em] text-[var(--ink)]">
                    {item.title}
                  </h3>
                  <p className="mt-2 text-[15px] leading-7 text-[var(--ink-soft)]">{item.body}</p>
                </article>
              );
            })}
          </div>
        </section>

        {/* About + compliance */}
        <section id="about" className="border-y border-[var(--border)] bg-[var(--surface-muted)]">
          <div className="mx-auto grid max-w-6xl gap-12 px-5 py-20 sm:px-6 sm:py-24 lg:grid-cols-[0.9fr_1.1fr]">
            <div>
              <p className="text-[13px] font-semibold uppercase tracking-[0.18em] text-[var(--brand-amber)]">
                About
              </p>
              <h2 className="mt-3 text-3xl font-semibold leading-tight tracking-[-0.03em] text-[var(--ink)] sm:text-4xl">
                Built for people who already use Alpaca.
              </h2>
              <p className="mt-4 text-[15px] leading-8 text-[var(--ink-soft)]">
                Vicu connects to your existing Alpaca brokerage account. It doesn&apos;t open accounts,
                hold funds, or give advice — it&apos;s a focused interface for the account you already
                have.
              </p>
              <ul className="mt-8 space-y-4">
                {appHighlights.map((item) => (
                  <li className="flex gap-3 text-[15px] leading-7 text-[var(--ink)]" key={item}>
                    <span
                      className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-[var(--brand-deep)]"
                      aria-hidden="true"
                    />
                    <span>{item}</span>
                  </li>
                ))}
              </ul>
            </div>

            <div className="rounded-3xl border border-[var(--border)] bg-[var(--surface)] p-7 sm:p-9">
              <h3 className="text-lg font-semibold tracking-[-0.01em] text-[var(--ink)]">
                Good to know
              </h3>
              <ul className="mt-5 space-y-4">
                {complianceNotes.map((item) => (
                  <li className="flex items-start gap-3 text-[15px] leading-7 text-[var(--ink-soft)]" key={item}>
                    <svg
                      className="mt-1 h-4 w-4 shrink-0 text-[var(--brand-amber)]"
                      viewBox="0 0 16 16"
                      fill="none"
                      aria-hidden="true"
                    >
                      <path
                        d="M6.5 11L3.5 8l1-1 2 2 5-5 1 1z"
                        fill="currentColor"
                      />
                    </svg>
                    <span>{item}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </section>

        {/* FAQ */}
        <section id="faq" className="mx-auto max-w-3xl px-5 py-20 sm:px-6 sm:py-24">
          <div className="text-center">
            <p className="text-[13px] font-semibold uppercase tracking-[0.18em] text-[var(--brand-amber)]">
              FAQ
            </p>
            <h2 className="mt-3 text-3xl font-semibold tracking-[-0.03em] text-[var(--ink)] sm:text-4xl">
              Common questions
            </h2>
          </div>
          <div className="mt-10">
            <Faq />
          </div>
        </section>

        {/* CTA / legal */}
        <section className="mx-auto max-w-6xl px-5 pb-24 sm:px-6">
          <div className="relative overflow-hidden rounded-[28px] bg-[var(--surface-ink)] px-7 py-12 sm:px-12 sm:py-14">
            <div
              className="pointer-events-none absolute -right-16 -top-20 h-72 w-72 rounded-full bg-[var(--brand)] opacity-20 blur-[90px]"
              aria-hidden="true"
            />
            <div className="relative grid gap-8 md:grid-cols-[1fr_auto] md:items-center">
              <div>
                <h2 className="text-2xl font-semibold tracking-[-0.02em] text-white sm:text-3xl">
                  The fine print
                </h2>
                <p className="mt-3 max-w-xl text-[15px] leading-7 text-white/65">
                  Read how Vicu handles your account access and data before you connect.
                </p>
              </div>
              <div className="flex flex-wrap gap-3">
                <a
                  className="focus-ring inline-flex items-center justify-center rounded-full bg-[var(--brand)] px-5 py-3 text-sm font-semibold text-[var(--on-brand)]"
                  href="/terms"
                >
                  Terms of Use
                </a>
                <a
                  className="focus-ring inline-flex items-center justify-center rounded-full border border-white/20 px-5 py-3 text-sm font-semibold text-white transition-colors hover:bg-white/10"
                  href="/privacy"
                >
                  Privacy Policy
                </a>
              </div>
            </div>
          </div>
        </section>
      </main>
      <Footer />
    </div>
  );
}
