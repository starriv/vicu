import type { Metadata } from "next";
import { LegalPage } from "@/components/LegalPage";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  title: "Terms of Use",
  description: "Terms of Use for Vicu."
};

export default function TermsPage() {
  return (
    <LegalPage
      title="Terms of Use"
      intro="These Terms govern access to and use of Vicu, an independent iOS application for Alpaca brokerage account workflows."
    >
      <h2>1. Acceptance of Terms</h2>
      <p>
        By accessing or using Vicu, you agree to these Terms of Use. If you do not agree, do not use
        the app or website.
      </p>

      <h2>2. Independent Third-Party Application</h2>
      <p>
        Vicu is independent third-party software. Vicu is not developed, sponsored, approved, or
        endorsed by Alpaca. Alpaca names, services, and trademarks belong to their respective owners.
      </p>

      <h2>3. Alpaca Account Access</h2>
      <p>
        Vicu is intended for users who have their own Alpaca brokerage account. When you connect an
        Alpaca account, you authorize Vicu to access account information and perform requested
        account actions within the permissions you grant. You are responsible for maintaining your
        Alpaca account, credentials, permissions, and compliance with Alpaca agreements.
      </p>

      <h2>4. No Investment Advice</h2>
      <p>
        Vicu provides software tools for viewing account data, market information, orders, positions,
        and related workflows. Vicu does not provide investment, financial, tax, legal, accounting, or
        trading advice. You are solely responsible for your investment decisions and for evaluating
        whether any transaction is appropriate for you.
      </p>

      <h2>5. Trading Risk</h2>
      <p>
        Trading and investing involve risk, including possible loss of principal. Market data may be
        delayed, incomplete, unavailable, or inaccurate. You should independently verify orders,
        positions, balances, and account activity with Alpaca before relying on them.
      </p>

      <h2>6. User Responsibilities</h2>
      <p>You agree that you will not:</p>
      <ul>
        <li>Use Vicu for unlawful, fraudulent, manipulative, or abusive activity.</li>
        <li>Attempt to bypass security controls, rate limits, or account restrictions.</li>
        <li>Use Vicu if you are not authorized to access the connected Alpaca account.</li>
        <li>Interfere with the operation, integrity, or security of Vicu or any connected service.</li>
      </ul>

      <h2>7. Account Credentials and Authorization</h2>
      <p>
        You are responsible for keeping your device, Alpaca credentials, and authorization grants
        secure. If you believe your account or device has been compromised, revoke access through
        Alpaca, remove saved credentials from Vicu, and contact the appropriate support channels.
      </p>

      <h2>8. Availability and Changes</h2>
      <p>
        Vicu may change, suspend, or discontinue features at any time. Alpaca API availability,
        permissions, account eligibility, and market access are controlled by Alpaca and may change
        independently of Vicu.
      </p>

      <h2>9. Disclaimers</h2>
      <p>
        Vicu is provided on an "as is" and "as available" basis without warranties of any kind,
        whether express, implied, or statutory, including warranties of merchantability, fitness for a
        particular purpose, title, and non-infringement.
      </p>

      <h2>10. Limitation of Liability</h2>
      <p>
        To the fullest extent permitted by law, Vicu and its developers will not be liable for any
        indirect, incidental, consequential, special, exemplary, or punitive damages, or for lost
        profits, trading losses, data loss, or service interruption arising from or related to your use
        of Vicu.
      </p>

      <h2>11. Termination</h2>
      <p>
        You may stop using Vicu at any time. We may suspend or terminate access if we believe your
        use violates these Terms, creates risk, or may harm Vicu, users, Alpaca, or other services.
      </p>

      <h2>12. Changes to These Terms</h2>
      <p>
        We may update these Terms from time to time. The updated version will be posted on this page
        with a revised "Last updated" date.
      </p>

      <h2>13. Contact</h2>
      <p>
        Questions about these Terms may be sent to{" "}
        <a className="font-semibold text-[var(--brand-amber)]" href={`mailto:${siteConfig.contactEmail}`}>
          {siteConfig.contactEmail}
        </a>
        .
      </p>
    </LegalPage>
  );
}
