import { and, asc, desc, eq, isNull } from "drizzle-orm";
import { db } from "@/lib/db";
import { accounts, transferRoutes } from "@/db/schema";
import { PageHeader } from "@/components/page-header";
import { TransferRoutesManager } from "./transfer-routes-manager";

export const dynamic = "force-dynamic";

export default async function TransferRoutesPage() {
  const [routes, allAccounts, manualAccts] = await Promise.all([
    db
      .select()
      .from(transferRoutes)
      .orderBy(desc(transferRoutes.priority), asc(transferRoutes.createdAt)),
    db.select().from(accounts).where(eq(accounts.archived, false)).orderBy(asc(accounts.name)),
    db
      .select()
      .from(accounts)
      .where(and(eq(accounts.archived, false), isNull(accounts.connectionId)))
      .orderBy(asc(accounts.name)),
  ]);

  return (
    <>
      <PageHeader
        title="Transfer routes"
        description="Route bank-feed entries like 'To Savings' to a manual destination account so internal pocket movements aren't counted as expenses."
      />
      <div className="p-6">
        <TransferRoutesManager
          routes={routes}
          accounts={allAccounts.map((a) => ({
            id: a.id,
            name: a.name,
            currency: a.currency,
            institution: a.institution,
            isManual: a.connectionId == null,
          }))}
          manualAccounts={manualAccts.map((a) => ({
            id: a.id,
            name: a.name,
            currency: a.currency,
          }))}
        />
      </div>
    </>
  );
}
