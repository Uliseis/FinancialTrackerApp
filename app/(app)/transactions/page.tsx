import { and, asc, desc, eq, ilike, or, sql, type SQL } from "drizzle-orm";
import { db } from "@/lib/db";
import { accounts, categories, transactions } from "@/db/schema";
import { PageHeader } from "@/components/page-header";
import type { CategoryKind } from "@/lib/income";
import { netForGroups } from "@/lib/shared-expenses";
import {
  TransactionsEmpty,
  TransactionsTable,
  type CategoryOption,
  type SharedExpenseSummary,
  type TransactionsTableRow,
} from "./transactions-table";

export const dynamic = "force-dynamic";

const PAGE_SIZE = 100;

function parsePage(raw: string | string[] | undefined): number {
  const v = Array.isArray(raw) ? raw[0] : raw;
  const n = Number.parseInt(v ?? "1", 10);
  return Number.isFinite(n) && n > 0 ? n : 1;
}

function firstParam(raw: string | string[] | undefined): string {
  const v = Array.isArray(raw) ? raw[0] : raw;
  return v ?? "";
}

export default async function TransactionsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const page = parsePage(sp.page);
  const q = firstParam(sp.q).trim();
  const showTransfers = firstParam(sp.transfers) === "show";

  const filters: SQL[] = [];
  if (!showTransfers) filters.push(eq(transactions.isTransfer, false));
  if (q) {
    const needle = `%${q}%`;
    filters.push(
      or(
        ilike(transactions.description, needle),
        ilike(transactions.counterparty, needle),
      )!,
    );
  }
  const whereClause = filters.length > 0 ? and(...filters) : undefined;

  const [totalRow] = await db
    .select({ count: sql<string>`count(*)` })
    .from(transactions)
    .where(whereClause);
  const total = Number(totalRow?.count ?? 0);
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const clampedPage = Math.min(page, totalPages);
  const offset = (clampedPage - 1) * PAGE_SIZE;

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
      .where(whereClause)
      .orderBy(desc(transactions.bookedAt))
      .limit(PAGE_SIZE)
      .offset(offset),
    db.select().from(categories).orderBy(asc(categories.name)),
  ]);

  const groupIds = Array.from(
    new Set(rows.map((r) => r.sharedExpenseGroupId).filter((v): v is string => Boolean(v))),
  );
  const groupSummaryMap = await netForGroups(groupIds);
  const groupSummaries: SharedExpenseSummary[] = Array.from(groupSummaryMap.values());

  const tableRows = rows as TransactionsTableRow[];
  const catOptions: CategoryOption[] = cats.map((c) => ({
    id: c.id,
    name: c.name,
    color: c.color,
    kind: c.kind as CategoryKind,
  }));

  const hasAnyTransactions = total > 0 || q.length > 0 || showTransfers;

  return (
    <>
      <PageHeader
        title="Transactions"
        description={`${total.toLocaleString()} matching · page ${clampedPage} of ${totalPages}`}
      />
      <div className="p-6">
        {!hasAnyTransactions ? (
          <TransactionsEmpty />
        ) : (
          <TransactionsTable
            rows={tableRows}
            categories={catOptions}
            sharedGroups={groupSummaries}
            page={clampedPage}
            totalPages={totalPages}
            total={total}
            pageSize={PAGE_SIZE}
            query={q}
            showTransfers={showTransfers}
          />
        )}
      </div>
    </>
  );
}
