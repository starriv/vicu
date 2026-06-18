export const siteConfig = {
  name: "Vicu",
  url: process.env.NEXT_PUBLIC_SITE_URL || "https://vicu.app",
  contactEmail: process.env.NEXT_PUBLIC_CONTACT_EMAIL || "support@vicu.app",
  lastUpdated: "June 18, 2026"
};

export const appHighlights = [
  "Portfolio value, cash, buying power, positions, and account activity in one place.",
  "Market search, live quotes, charts, news, and options views.",
  "Share and notional order workflows with buying power in view.",
  "A connection you control, with credentials stored in the device Keychain."
];

export const complianceNotes = [
  "Vicu does not open Alpaca accounts.",
  "Vicu does not hold customer cash or securities.",
  "Vicu does not provide investment, tax, legal, or financial advice.",
  "Trading and investing involve risk, including possible loss of principal."
];
