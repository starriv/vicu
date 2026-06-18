"use client";

import * as Accordion from "@radix-ui/react-accordion";
import { Plus } from "lucide-react";

const items = [
  {
    value: "affiliation",
    title: "Is Vicu affiliated with Alpaca?",
    body:
      "No. Vicu is independent third-party software. Alpaca is a trademark of its respective owner, and Vicu is not developed, sponsored, or endorsed by Alpaca."
  },
  {
    value: "advice",
    title: "Does Vicu provide investment advice?",
    body:
      "No. Vicu provides software tools for account access, market context, and order workflows. It does not recommend trades, portfolios, strategies, or account actions."
  },
  {
    value: "funds",
    title: "Can Vicu deposit or withdraw funds?",
    body:
      "The current app is designed for Trading API account workflows. Alpaca account funding is handled through Alpaca's own dashboard unless a separate approved Broker API integration is implemented."
  },
  {
    value: "credentials",
    title: "Where are my credentials stored?",
    body:
      "On your device. The current release keeps Alpaca credentials in the iOS Keychain, and you control the connection — you can revoke access through Alpaca or remove the credentials from the app at any time."
  }
];

export function Faq() {
  return (
    <Accordion.Root
      type="single"
      collapsible
      defaultValue="affiliation"
      className="divide-y divide-[var(--border)] overflow-hidden rounded-2xl border border-[var(--border)] bg-[var(--surface)]"
    >
      {items.map((item) => (
        <Accordion.Item value={item.value} key={item.value}>
          <Accordion.Header>
            <Accordion.Trigger className="focus-ring group flex w-full items-center justify-between gap-4 px-5 py-5 text-left text-[16px] font-semibold text-[var(--ink)] sm:px-6">
              {item.title}
              <span
                aria-hidden="true"
                className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-[var(--border-strong)] text-[var(--ink-soft)] transition-colors duration-200 group-data-[state=open]:border-[var(--brand-deep)] group-data-[state=open]:bg-[var(--brand)] group-data-[state=open]:text-[var(--on-brand)]"
              >
                <Plus
                  size={16}
                  className="transition-transform duration-200 group-data-[state=open]:rotate-45"
                />
              </span>
            </Accordion.Trigger>
          </Accordion.Header>
          <Accordion.Content className="overflow-hidden data-[state=closed]:animate-acc-up data-[state=open]:animate-acc-down">
            <p className="px-5 pb-5 text-[15px] leading-7 text-[var(--ink-soft)] sm:px-6">{item.body}</p>
          </Accordion.Content>
        </Accordion.Item>
      ))}
    </Accordion.Root>
  );
}
