import { asc, desc, eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { accounts, categories, transactions } from "@/db/schema";
import { PageHeader } from "@/components/page-header";
import {
  TransactionsEmpty,
  TransactionsTable,
  type CategoryOption,
  type TransactionsTableRow,
} from "./transactions-table";

export const dynamic = "force-dynamic";

const PAGE_SIZE = 200;

export default async function TransactionsPage() {
  const [rows, cats] = await Promise.all([
    db
      .select({
        id: transactions.id,
        bookedAt: transactions.bookedAt,
        amount: transactions.amount,
        currency: transactions.currency,
        amountEur: transactions.amountEur,
        direction: transactions.direction,
        description: transactions.description,
        counterparty: transactions.counterparty,
        categoryId: transactions.categoryId,
        categorySource: transactions.categorySource,
        isTransfer: transactions.isTransfer,
        accountId: transactions.accountId,
        accountName: accounts.name,
        institution: accounts.institution,
      })
      .from(transactions)
      .leftJoin(accounts, eq(transactions.accountId, accounts.id))
      .orderBy(desc(transactions.bookedAt))
      .limit(PAGE_SIZE),
    db.select().from(categories).orderBy(asc(categories.name)),
  ]);

  const tableRows = rows as TransactionsTableRow[];
  const catOptions: CategoryOption[] = cats.map((c) => ({
    id: c.id,
    name: c.name,
    color: c.color,
    kind: c.kind as "expense" | "income",
  }));

  return (
    <>
      <PageHeader
        title="Transactions"
        description={`Most recent ${PAGE_SIZE} synced rows. Internal transfers are hidden by default.`}
      />
      <div className="p-6">
        {tableRows.length === 0 ? (
          <TransactionsEmpty />
        ) : (
          <TransactionsTable rows={tableRows} categories={catOptions} />
        )}
      </div>
    </>
  );
}
