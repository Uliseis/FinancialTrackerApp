import { db } from "@/lib/db";
import { accounts, transactions } from "@/db/schema";
import { desc, eq } from "drizzle-orm";
import { PageHeader } from "@/components/page-header";
import {
  TransactionsEmpty,
  TransactionsTable,
  type TransactionsTableRow,
} from "./transactions-table";

export const dynamic = "force-dynamic";

const PAGE_SIZE = 100;

export default async function TransactionsPage() {
  const rows = (await db
    .select({
      id: transactions.id,
      bookedAt: transactions.bookedAt,
      amount: transactions.amount,
      currency: transactions.currency,
      direction: transactions.direction,
      description: transactions.description,
      counterparty: transactions.counterparty,
      accountName: accounts.name,
      institution: accounts.institution,
    })
    .from(transactions)
    .leftJoin(accounts, eq(transactions.accountId, accounts.id))
    .orderBy(desc(transactions.bookedAt))
    .limit(PAGE_SIZE)) as TransactionsTableRow[];

  return (
    <>
      <PageHeader
        title="Transactions"
        description={`Most recent ${PAGE_SIZE} synced rows.`}
      />
      <div className="p-6">
        {rows.length === 0 ? <TransactionsEmpty /> : <TransactionsTable rows={rows} />}
      </div>
    </>
  );
}
