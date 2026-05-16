import Link from "next/link";

export const metadata = {
  title: "Privacy Policy — Financial Tracker",
};

const LAST_UPDATED = "10 May 2026";
const CONTACT_EMAIL = "usbrgr@gmail.com";

export default function PrivacyPage() {
  return (
    <main className="container max-w-3xl py-12">
      <div className="mb-8">
        <Link
          href="/"
          className="text-sm text-[var(--color-muted-foreground)] underline"
        >
          ← Home
        </Link>
      </div>
      <article className="prose prose-sm max-w-none space-y-6">
        <header>
          <h1 className="text-3xl font-semibold tracking-tight">Privacy Policy</h1>
          <p className="text-sm text-[var(--color-muted-foreground)]">
            Last updated: {LAST_UPDATED}
          </p>
        </header>

        <section>
          <h2 className="text-xl font-semibold">1. About this service</h2>
          <p>
            Financial Tracker is a private, single-user personal finance dashboard
            operated by the individual identified below for their own use. It is
            not a commercial product and is not offered to the public.
          </p>
          <p>
            Bank account information is accessed under the EU revised Payment
            Services Directive (PSD2) through{" "}
            <a
              href="https://enablebanking.com/"
              className="underline"
              rel="noreferrer"
              target="_blank"
            >
              Enable Banking
            </a>
            , a regulated Account Information Service Provider (AISP) acting as a
            technical service provider to the operator. The operator does not
            initiate payments and does not store payment credentials.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">2. Data controller</h2>
          <p>
            The operator of this service is the data controller and the sole user
            of the data. Contact:{" "}
            <a className="underline" href={`mailto:${CONTACT_EMAIL}`}>
              {CONTACT_EMAIL}
            </a>
            .
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">3. Data processed</h2>
          <ul className="list-disc pl-6">
            <li>
              <strong>Account information</strong> retrieved from connected
              banks: account name, IBAN, currency, balance, and balance
              reference dates.
            </li>
            <li>
              <strong>Transaction information</strong> retrieved from connected
              banks: amount, currency, booking and value dates, counterparty
              name, remittance information, and bank transaction codes.
            </li>
            <li>
              <strong>Authentication metadata</strong> required to maintain a
              connection with each bank: the consent identifier
              (<code>session_id</code>), consent expiry, and the institution
              name.
            </li>
            <li>
              <strong>Sign-in identity</strong>: the email address associated
              with the operator’s GitHub account, used solely to gate access to
              the operator&apos;s own deployment.
            </li>
          </ul>
          <p>
            No payment credentials (passwords, card numbers, bank login
            credentials) are ever requested, transmitted, or stored. Bank
            authentication takes place exclusively on the bank&apos;s own
            authorization page during the consent flow.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">4. Purposes and legal basis</h2>
          <p>
            Data is processed for the sole purpose of presenting a consolidated
            view of the operator&apos;s personal finances. Legal basis under the
            GDPR is Article 6(1)(a) — explicit consent given through the bank&apos;s
            own PSD2 authorization flow — and Article 6(1)(f) — legitimate
            interest of the operator in managing their own finances.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">5. Storage and security</h2>
          <p>
            Data is stored in a managed Postgres database (Neon, EU region) over
            TLS. Sensitive tokens, where present, are encrypted at rest using
            AES-256-GCM with keys never exposed in source control. Access to
            the application is restricted to a single email address; all other
            sign-ins are rejected at the authentication callback. The
            application is hosted on Vercel; data in transit uses HTTPS.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">6. Retention</h2>
          <p>
            Account, transaction, and connection data is retained for as long as
            the operator finds it useful for personal record-keeping, in line
            with reasonable accounting and tax retention periods, and is deleted
            on request. PSD2 consents expire automatically (typically 90 to 180
            days depending on the bank); after expiry no further data can be
            fetched until the consent is renewed.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">7. Sharing</h2>
          <p>
            Data is not sold, shared, or otherwise disclosed to third parties.
            The only processors involved in delivering the service are:
          </p>
          <ul className="list-disc pl-6">
            <li>Enable Banking (Finland) — PSD2 connectivity provider</li>
            <li>Neon (EU) — managed Postgres hosting</li>
            <li>Vercel (US/EU) — application hosting</li>
            <li>GitHub (US) — sign-in identity provider</li>
          </ul>
        </section>

        <section>
          <h2 className="text-xl font-semibold">8. Your rights</h2>
          <p>
            Because this service is single-user, the operator and the data
            subject are the same person. Where data subject rights under the
            GDPR — access, rectification, erasure, restriction, portability,
            objection — would apply, they are exercised directly by the
            operator on their own data.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">9. Withdrawing consent</h2>
          <p>
            Consent given to a bank can be revoked at any time through the
            bank&apos;s own channels. The corresponding connection in this
            application can be removed by deleting the connection from the
            Connections page, which deletes the associated accounts and
            transactions.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">10. Changes to this policy</h2>
          <p>
            This policy may be updated as the application evolves. The
            &quot;Last updated&quot; date at the top will reflect the latest
            revision.
          </p>
        </section>
      </article>
    </main>
  );
}
