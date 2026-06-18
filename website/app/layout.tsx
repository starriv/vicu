import type { Metadata } from "next";
import type { ReactNode } from "react";
import "./globals.css";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  metadataBase: new URL(siteConfig.url),
  title: {
    default: `${siteConfig.name} | Independent iOS client for Alpaca accounts`,
    template: `%s | ${siteConfig.name}`
  },
  description:
    "Vicu is an independent iOS app for monitoring portfolios, market data, orders, and account activity for Alpaca brokerage accounts.",
  openGraph: {
    title: siteConfig.name,
    description:
      "A focused iOS client for Alpaca brokerage account monitoring, market research, and trading workflows.",
    url: siteConfig.url,
    siteName: siteConfig.name,
    locale: "en_US",
    type: "website"
  },
  robots: {
    index: true,
    follow: true
  }
};

export default function RootLayout({
  children
}: Readonly<{
  children: ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
