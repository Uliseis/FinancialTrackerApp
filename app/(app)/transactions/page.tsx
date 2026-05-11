import { asc, desc, eq, inArray, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  accounts,
  categories,
  sharedExpenseGroups,
  transactions,
} from "@/db/schema";
import { PageHeader } from "@/components/page-header";
import type { CategoryKind } from "@/lib/income";
import {
  TransactionsEmpty,
  TransactionsTable,
  type CategoryOption,
  type SharedExpenseSummary,
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
        sharedExpenseGroupId: transactions.sharedExpenseGroupId,
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

  const groupIds = Array.from(
    new Set(rows.map((r) => r.sharedExpenseGroupId).filter((v): v is string => Boolean(v))),
  );
  const groupSummaries: SharedExpenseSummary[] =
    groupIds.length === 0
      ? []
      : await (async () => {
          const groups = await db
            .select()
            .from(sharedExpenseGroups)
            .where(inArray(sharedExpenseGroups.id, groupIds));
          const sums = await db
            .select({
              groupId: transactions.sharedExpenseGroupId,
              primaryEur: sql<string>`coalesce(sum(case when ${transactions.direction} = 'debit' then ${transactions.amountEur} else 0 end), 0)`,
              creditEur: sql<string>`coalesce(sum(case when ${transactions.direction} = 'credit' then ${transactions.amountEur} else 0 end), 0)`,
            })
            .from(transactions)
            .where(inArray(transactions.sharedExpenseGroupId, groupIds))
            .groupBy(transactions.sharedExpenseGroupId);
          const sumById = new Map(sums.map((s) => [s.groupId!, s]));
          return groups.map((g) => {
            const s = sumById.get(g.id);
            const gross = s ? Math.abs(Number(s.primaryEur)) : 0;
            const reimbursed = s ? Math.abs(Number(s.creditEur)) : 0;
            return {
              id: g.id,
              label: g.label,
              primaryTxId: g.primaryTxId,
              gross,
              reimbursed,
              net: gross - reimbursed,
            };
          });
        })();

  const tableRows = rows as TransactionsTableRow[];
  const catOptions: CategoryOption[] = cats.map((c) => ({
    id: c.id,
    name: c.name,
    color: c.color,
    kind: c.kind as CategoryKind,
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
          <TransactionsTable
            rows={tableRows}
            categories={catOptions}
            sharedGroups={groupSummaries}
          />
        )}
      </div>
    </>
  );
}
