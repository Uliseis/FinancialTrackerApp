import Link from "next/link";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
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
    <main className="container py-10">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Connect a bank</h1>
          <p className="text-sm text-[var(--color-muted-foreground)]">
            Pick your bank to authorize read access via Enable Banking / PSD2.
          </p>
        </div>
        <Button asChild variant="outline">
          <Link href="/">Back</Link>
        </Button>
      </div>

      <Card className="mb-6">
        <CardHeader>
          <CardTitle>Country</CardTitle>
          <CardDescription>Filter institutions by country.</CardDescription>
        </CardHeader>
        <CardContent className="flex flex-wrap gap-2">
          {SUPPORTED_COUNTRIES.map((c) => (
            <Button
              key={c.code}
              asChild
              variant={c.code === country ? "default" : "outline"}
              size="sm"
            >
              <Link href={`/connect?country=${c.code}`}>{c.name}</Link>
            </Button>
          ))}
        </CardContent>
      </Card>

      {error ? (
        <Card>
          <CardHeader>
            <CardTitle>Could not load institutions</CardTitle>
            <CardDescription>
              Check your Enable Banking credentials in env vars.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <pre className="whitespace-pre-wrap text-xs text-[var(--color-destructive)]">
              {error}
            </pre>
          </CardContent>
        </Card>
      ) : (
        <ConnectForm aspsps={aspsps} country={country} />
      )}
    </main>
  );
}
