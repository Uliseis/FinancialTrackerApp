import Link from "next/link";
import { AlertCircle } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { PageHeader } from "@/components/page-header";
import { EnableBankingClient, type Aspsp } from "@/lib/enablebanking";
import { ConnectForm } from "./connect-form";

export const dynamic = "force-dynamic";

const SUPPORTED_COUNTRIES = [
  { code: "ES", name: "Spain" },
  { code: "GB", name: "United Kingdom" },
  { code: "PT", name: "Portugal" },
  { code: "DE", name: "Germany" },
  { code: "FR", name: "France" },
  { code: "IT", name: "Italy" },
  { code: "IE", name: "Ireland" },
  { code: "NL", name: "Netherlands" },
];

export default async function ConnectPage({
  searchParams,
}: {
  searchParams: Promise<{ country?: string }>;
}) {
  const { country: rawCountry } = await searchParams;
  const country = (rawCountry ?? "ES").toUpperCase();

  let aspsps: Aspsp[] = [];
  let error: string | null = null;
  try {
    const client = new EnableBankingClient();
    aspsps = await client.listAspsps({ country, psuType: "personal" });
  } catch (err) {
    error = err instanceof Error ? err.message : "unknown";
  }

  return (
    <>
      <PageHeader
        title="Connect a bank"
        description="Pick your bank to authorize read access via Enable Banking / PSD2."
      />

      <div className="space-y-6 p-6">
        <div className="flex flex-wrap gap-1.5 rounded-lg border border-[var(--color-border)] bg-[var(--color-muted)]/40 p-1.5">
          {SUPPORTED_COUNTRIES.map((c) => {
            const active = c.code === country;
            return (
              <Button
                key={c.code}
                asChild
                variant={active ? "default" : "ghost"}
                size="sm"
                className={active ? "" : "text-[var(--color-muted-foreground)]"}
              >
                <Link href={`/connect?country=${c.code}`}>{c.name}</Link>
              </Button>
            );
          })}
        </div>

        {error ? (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2">
                <AlertCircle className="h-5 w-5 text-[var(--color-destructive)]" />
                Could not load institutions
              </CardTitle>
              <CardDescription>
                Check your Enable Banking credentials in env vars.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <pre className="whitespace-pre-wrap rounded-md bg-[var(--color-muted)] p-3 text-xs text-[var(--color-destructive)]">
                {error}
              </pre>
            </CardContent>
          </Card>
        ) : (
          <ConnectForm aspsps={aspsps} country={country} />
        )}
      </div>
    </>
  );
}
