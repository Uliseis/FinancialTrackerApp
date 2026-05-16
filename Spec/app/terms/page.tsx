import Link from "next/link";

export const metadata = {
  title: "Terms of Use — Financial Tracker",
};

const LAST_UPDATED = "10 May 2026";
const CONTACT_EMAIL = "usbrgr@gmail.com";

export default function TermsPage() {
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
          <h1 className="text-3xl font-semibold tracking-tight">Terms of Use</h1>
          <p className="text-sm text-[var(--color-muted-foreground)]">
            Last updated: {LAST_UPDATED}
          </p>
        </header>

        <section>
          <h2 className="text-xl font-semibold">1. Nature of the service</h2>
          <p>
            Financial Tracker is a personal, single-user dashboard operated by
            its sole user for the purpose of viewing their own bank, broker,
            and crypto account information. It is not a commercial product, is
            not offered to the public, and is not a substitute for advice from
            a qualified financial professional.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">2. Eligibility and access</h2>
          <p>
            Access is restricted by an email allowlist enforced at sign-in.
            Only the operator may use the service. Any attempt by another
            person to access it is unauthorized.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">3. Bank connectivity</h2>
          <p>
            Bank account data is retrieved through{" "}
            <a
              href="https://enablebanking.com/"
              className="underline"
              rel="noreferrer"
              target="_blank"
            >
              Enable Banking
            </a>
            , a regulated PSD2 Account Information Service Provider. The
            operator authorizes each bank connection through that bank&apos;s
            own PSD2 authorization flow and may revoke the consent at any time
            from the bank&apos;s own channels.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">4. Accuracy</h2>
          <p>
            The information shown is provided as-is, sourced from the operator&apos;s
            banks via PSD2 APIs. It may be incomplete, delayed, or affected by
            connectivity issues with the underlying banks. The operator is
            responsible for verifying any figure before relying on it for
            decisions.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">5. No warranty</h2>
          <p>
            The service is provided without warranties of any kind, express or
            implied, including merchantability, fitness for a particular
            purpose, or non-infringement. To the maximum extent permitted by
            law, the operator disclaims all liability for any direct, indirect,
            incidental, or consequential loss arising from use or inability to
            use the service.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">6. Privacy</h2>
          <p>
            Use of the service is governed by the{" "}
            <Link href="/privacy" className="underline">
              Privacy Policy
            </Link>
            , which forms part of these terms.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">7. Termination</h2>
          <p>
            The operator may discontinue the service at any time. Stored data
            can be deleted at any time by removing connections from the
            Connections page or by dropping the underlying database.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">8. Governing law</h2>
          <p>
            These terms are governed by the laws of Spain, without regard to
            conflict-of-laws principles.
          </p>
        </section>

        <section>
          <h2 className="text-xl font-semibold">9. Contact</h2>
          <p>
            For any question regarding these terms, contact{" "}
            <a className="underline" href={`mailto:${CONTACT_EMAIL}`}>
              {CONTACT_EMAIL}
            </a>
            .
          </p>
        </section>
      </article>
    </main>
  );
}
