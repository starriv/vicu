import type { Metadata } from "next";
import { LegalPage } from "@/components/LegalPage";
import { siteConfig } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "Privacy Policy for Vicu."
};

export default function PrivacyPage() {
  return (
    <LegalPage
      title="Privacy Policy"
      intro="This Privacy Policy explains how Vicu handles information when you use the app and website."
    >
      <h2>1. Overview</h2>
      <p>
        Vicu is an independent iOS application for Alpaca brokerage account workflows. This Policy
        describes the types of information Vicu may process, how that information is used, and the
        choices available to users.
      </p>

      <h2>2. Information You Provide or Authorize</h2>
      <p>Depending on the features you use, Vicu may process:</p>
      <ul>
        <li>Alpaca account connection information, authorization grants, or API credentials.</li>
        <li>Account data returned by Alpaca, such as balances, buying power, positions, orders, and activities.</li>
        <li>Preferences such as appearance, language, notification settings, and app configuration.</li>
        <li>Messages or support requests you send to us.</li>
      </ul>

      <h2>3. Local Credential Storage</h2>
      <p>
        In the current iOS app, user-provided Alpaca API credentials are stored locally in the iOS
        Keychain on the user's device. If Vicu enables Alpaca Connect OAuth in the future,
        authorization tokens may be stored securely and used only to provide the account connection
        features requested by the user.
      </p>

      <h2>4. How Information Is Used</h2>
      <p>Vicu uses information to:</p>
      <ul>
        <li>Connect to your Alpaca account with your authorization.</li>
        <li>Display account, portfolio, market, order, and activity information.</li>
        <li>Submit user-requested order actions to Alpaca.</li>
        <li>Maintain security, diagnose issues, improve reliability, and respond to support requests.</li>
      </ul>

      <h2>5. Information Sharing</h2>
      <p>
        Vicu does not sell personal information. Vicu may share information only when necessary to
        operate requested features, comply with law, protect rights and security, or communicate with
        service providers that help operate the app or website.
      </p>

      <h2>6. Alpaca and Third-Party Services</h2>
      <p>
        When you connect an Alpaca account, Alpaca processes your information under its own terms and
        privacy policies. Vicu is not responsible for Alpaca's services, policies, or data practices.
        You can revoke access to connected applications through Alpaca where supported.
      </p>

      <h2>7. Website Data</h2>
      <p>
        This website may process standard technical information such as IP address, browser type,
        device information, pages visited, and timestamps through hosting, security, or analytics
        providers. This information is used to operate, secure, and improve the website.
      </p>

      <h2>8. Data Retention</h2>
      <p>
        Vicu retains information only as long as reasonably needed for the purposes described in this
        Policy, unless a longer retention period is required or permitted by law. Local data can be
        removed by deleting saved credentials, clearing app data, or uninstalling the app.
      </p>

      <h2>9. Security</h2>
      <p>
        Vicu uses reasonable technical and organizational measures designed to protect information.
        No method of transmission or storage is completely secure, and we cannot guarantee absolute
        security.
      </p>

      <h2>10. Children</h2>
      <p>
        Vicu is not directed to children under 13 and is intended for users who are permitted to hold
        and access their own Alpaca brokerage account. Do not use Vicu if you are not legally allowed
        to do so.
      </p>

      <h2>11. International Users</h2>
      <p>
        Information may be processed in countries other than your country of residence. By using Vicu,
        you understand that information may be processed where Vicu, hosting providers, or connected
        services operate.
      </p>

      <h2>12. Your Choices</h2>
      <p>
        You may disconnect your Alpaca account, remove saved credentials, revoke authorization where
        supported by Alpaca, uninstall the app, or contact us with privacy questions.
      </p>

      <h2>13. Changes to This Policy</h2>
      <p>
        We may update this Privacy Policy from time to time. The updated version will be posted on
        this page with a revised "Last updated" date.
      </p>

      <h2>14. Contact</h2>
      <p>
        Privacy questions may be sent to{" "}
        <a className="font-semibold text-[var(--brand-amber)]" href={`mailto:${siteConfig.contactEmail}`}>
          {siteConfig.contactEmail}
        </a>
        .
      </p>
    </LegalPage>
  );
}
