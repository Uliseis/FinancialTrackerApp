import { and, asc, desc, eq, gte, ilike, inArray, isNull, lte, or, sql, type SQL } from "drizzle-orm";
import { alias } from "drizzle-orm/pg-core";
import { db } from "@/lib/db";
import { accounts, categories, transactions } from "@/db/schema";
import { PageHeader } from "@/components/page-header";
import type { CategoryKind } from "@/lib/income";
import { netForGroups } from "@/lib/shared-expenses";
import {
  accountInSpaceClause,
  getDefaultSpaceId,
  listSpaces,
  resolveSpaceId,
} from "@/lib/spaces";
import { SpaceTabs } from "../space-tabs";
import {
  TransactionsEmpty,
  TransactionsTable,
  type CategoryOption,
  type FilterAccountOption,
  type ManualAccountOption,
  type SharedExpenseSummary,
  type SortKey,
  type TransactionsTableRow,
} from "./transactions-table";

export const dynamic = "force-dynamic";

const PAGE_SIZE = 100;
const VALID_SORTS = new Set<SortKey>(["date:desc", "date:asc", "amount:desc", "amount:asc"]);

function parsePage(raw: string | string[] | undefined): number {
  const v = Array.isArray(raw) ? raw[0] : raw;
  const n = Number.parseInt(v ?? "1", 10);
  return Number.isFinite(n) && n > 0 ? n : 1;
}

function firstParam(raw: string | string[] | undefined): string {
  const v = Array.isArray(raw) ? raw[0] : raw;
  return v ?? "";
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function parseUuidList(raw: string | string[] | undefined): string[] {
  const v = firstParam(raw);
  if (!v) return [];
  return v.split(",").map((s) => s.trim()).filter((s) => UUID_RE.test(s));
}

function parseDate(raw: string | string[] | undefined): Date | null {
  const v = firstParam(raw);
  if (!v) return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

function parseSort(raw: string | string[] | undefined): SortKey {
  const v = firstParam(raw) as SortKey;
  return VALID_SORTS.has(v) ? v : "date:desc";
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
  const sort = parseSort(sp.sort);
  const accountFilter = parseUuidList(sp.accounts);
  const categoryFilterRaw = firstParam(sp.categories);
  const includeUncategorized = categoryFilterRaw
    .split(",")
    .map((s) => s.trim())
    .includes("none");
  const categoryFilter = parseUuidList(sp.categories);
  const directionRaw = firstParam(sp.direction);
  const direction: "credit" | "debit" | null =
    directionRaw === "credit" || directionRaw === "debit" ? directionRaw : null;
  const from = parseDate(sp.from);
  const toRaw = parseDate(sp.to);
  const to = toRaw ? new Date(toRaw.getTime() + 24 * 60 * 60 * 1000 - 1) : null;

  const [spaces, defaultSpaceId, currentSpaceId] = await Promise.all([
    listSpaces(),
    getDefaultSpaceId(),
    resolveSpaceId(sp.space),
  ]);

  const spaceAccountRows = await db
    .select({
      id: accounts.id,
      name: accounts.name,
      currency: accounts.currency,
      institution: accounts.institution,
      connectionId: accounts.connectionId,
    })
    .from(accounts)
    .where(
      and(
        accountInSpaceClause(currentSpaceId, defaultSpaceId),
        eq(accounts.archived, false),
        eq(accounts.excluded, false),
      ),
    )
    .orderBy(asc(accounts.name));
  const spaceAccountIds = spaceAccountRows.map((r) => r.id);

  let effectiveAccountIds: string[];
  if (accountFilter.length > 0) {
    const allowed = new Set(spaceAccountIds);
    effectiveAccountIds = accountFilter.filter((id) => allowed.has(id));
  } else {
    effectiveAccountIds = spaceAccountIds;
  }

  const filters: SQL[] = [isNull(transactions.routedFromTxId)];
  if (effectiveAccountIds.length === 0) {
    filters.push(sql`false`);
  } else {
    filters.push(inArray(transactions.accountId, effectiveAccountIds));
  }
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
  if (direction) filters.push(eq(transactions.direction, direction));
  if (from) filters.push(gte(transactions.bookedAt, from));
  if (to) filters.push(lte(transactions.bookedAt, to));
  if (categoryFilter.length > 0 || includeUncategorized) {
    const catClauses: SQL[] = [];
    if (categoryFilter.length > 0) {
      catClauses.push(inArray(transactions.categoryId, categoryFilter));
    }
    if (includeUncategorized) {
      catClauses.push(isNull(transactions.categoryId));
    }
    const combined = catClauses.length === 1 ? catClauses[0] : or(...catClauses);
    if (combined) filters.push(combined);
  }
  const whereClause = and(...filters);

  const [totalRow] = await db
    .select({ count: sql<string>`count(*)` })
    .from(transactions)
    .where(whereClause);
  const total = Number(totalRow?.count ?? 0);
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const clampedPage = Math.min(page, totalPages);
  const offset = (clampedPage - 1) * PAGE_SIZE;

  const mirrorTx = alias(transactions, "mirror_tx");
  const mirrorAccount = alias(accounts, "mirror_account");

  const orderClauses: SQL[] = (() => {
    switch (sort) {
      case "date:asc":
        return [
          asc(transactions.bookedAt),
          asc(transactions.createdAt),
          asc(transactions.id),
        ];
      case "amount:desc":
        return [
          sql`ABS(${transactions.amountEur}) DESC NULLS LAST`,
          desc(transactions.bookedAt),
          desc(transactions.id),
        ];
      case "amount:asc":
        return [
          sql`ABS(${transactions.amountEur}) ASC NULLS LAST`,
          desc(transactions.bookedAt),
          desc(transactions.id),
        ];
      case "date:desc":
      default:
        return [
          desc(transactions.bookedAt),
          desc(transactions.createdAt),
          desc(transactions.id),
        ];
    }
  })();

  const [rows, cats, manualAccts] = await Promise.all([
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
        routedFromTxId: transactions.routedFromTxId,
        accountId: transactions.accountId,
        accountName: accounts.name,
        institution: accounts.institution,
        routedToAccountId: mirrorAccount.id,
        routedToAccountName: mirrorAccount.name,
      })
      .from(transactions)
      .leftJoin(accounts, eq(transactions.accountId, accounts.id))
      .leftJoin(mirrorTx, eq(mirrorTx.routedFromTxId, transactions.id))
      .leftJoin(mirrorAccount, eq(mirrorAccount.id, mirrorTx.accountId))
      .where(whereClause)
      .orderBy(...orderClauses)
      .limit(PAGE_SIZE)
      .offset(offset),
    db.select().from(categories).orderBy(asc(categories.name)),
    db
      .select({
        id: accounts.id,
        name: accounts.name,
        currency: accounts.currency,
        institution: accounts.institution,
      })
      .from(accounts)
      .where(and(eq(accounts.archived, false), isNull(accounts.connectionId)))
      .orderBy(asc(accounts.name)),
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
  const manualOptions: ManualAccountOption[] = manualAccts.map((a) => ({
    id: a.id,
    name: a.name,
    currency: a.currency,
    institution: a.institution,
  }));
  const filterAccountOptions: FilterAccountOption[] = spaceAccountRows.map((a) => ({
    id: a.id,
    name: a.name,
    institution: a.institution,
  }));

  const hasFilters =
    accountFilter.length > 0 ||
    categoryFilter.length > 0 ||
    includeUncategorized ||
    direction != null ||
    from != null ||
    to != null ||
    sort !== "date:desc";
  const hasAnyTransactions = total > 0 || q.length > 0 || showTransfers || hasFilters;

  return (
    <>
      <PageHeader
        title="Transactions"
        description={`${total.toLocaleString()} matching · page ${clampedPage} of ${totalPages}`}
      />
      <div className="space-y-4 p-6">
        <SpaceTabs
          spaces={spaces}
          currentSpaceId={currentSpaceId}
          defaultSpaceId={defaultSpaceId}
        />
        {!hasAnyTransactions ? (
          <TransactionsEmpty />
        ) : (
          <TransactionsTable
            rows={tableRows}
            categories={catOptions}
            sharedGroups={groupSummaries}
            manualAccounts={manualOptions}
            filterAccounts={filterAccountOptions}
            page={clampedPage}
            totalPages={totalPages}
            total={total}
            pageSize={PAGE_SIZE}
            query={q}
            showTransfers={showTransfers}
            sort={sort}
            accountFilter={accountFilter}
            categoryFilter={categoryFilter}
            includeUncategorized={includeUncategorized}
            direction={direction}
            from={firstParam(sp.from)}
            to={firstParam(sp.to)}
          />
        )}
      </div>
    </>
  );
}
