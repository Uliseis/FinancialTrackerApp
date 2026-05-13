import { asc } from "drizzle-orm";
import { db } from "@/lib/db";
import { accountGroups, accounts, categories } from "@/db/schema";
import { PageHeader } from "@/components/page-header";
import {
  computeAccountBalancesEur,
  computeAccountNativeBalances,
  computeMonthlyExpenseEurByAccount,
} from "@/lib/accounts";
import { getRate } from "@/lib/fx";
import { getDefaultSpaceId, listSpaces } from "@/lib/spaces";
import { monthStart } from "@/lib/utils";
import { AccountsManager } from "./accounts-manager";
import { SpacesManager } from "./spaces-manager";

export const dynamic = "force-dynamic";

export default async function AccountsPage() {
  const [acctRows, groupRows, spaceRows, defaultSpaceId, categoryRows] = await Promise.all([
    db.select().from(accounts).orderBy(asc(accounts.name)),
    db.select().from(accountGroups).orderBy(asc(accountGroups.sortOrder)),
    listSpaces(),
    getDefaultSpaceId(),
    db
      .select({ id: categories.id, name: categories.name, color: categories.color })
      .from(categories)
      .orderBy(asc(categories.name)),
  ]);

  const rateCache = new Map<string, number>();
  async function rateFor(ccy: string): Promise<number> {
    const key = ccy.toUpperCase();
    if (rateCache.has(key)) return rateCache.get(key)!;
    const r = await getRate(new Date(), key);
    rateCache.set(key, r ?? 1);
    return r ?? 1;
  }

  const activeRows = acctRows.filter((a) => !a.archived);
  const now = new Date();
  const start = monthStart(now);
  const end = monthStart(now, 1);
  const [eurMap, nativeMap, expenseMap] = await Promise.all([
    computeAccountBalancesEur(activeRows, { rateFor }),
    computeAccountNativeBalances(activeRows),
    computeMonthlyExpenseEurByAccount(
      activeRows.map((a) => a.id),
      start,
      end,
    ),
  ]);

  const nativeBalances: Record<string, string | null> = {};
  for (const a of acctRows) {
    const v = nativeMap.get(a.id);
    nativeBalances[a.id] = v != null ? v.toFixed(2) : a.balance;
  }
  const eurBalances: Record<string, number> = {};
  for (const [id, v] of eurMap) eurBalances[id] = v;
  const eurExpenses: Record<string, number> = {};
  for (const [id, v] of expenseMap) eurExpenses[id] = v;

  return (
    <>
      <PageHeader
        title="Accounts"
        description="Group accounts to roll up balances on the dashboard."
      />
      <div className="space-y-6 p-6">
        <SpacesManager spaces={spaceRows} />
        <AccountsManager
          accounts={acctRows}
          groups={groupRows}
          spaces={spaceRows}
          defaultSpaceId={defaultSpaceId}
          nativeBalances={nativeBalances}
          eurBalances={eurBalances}
          eurExpenses={eurExpenses}
          categories={categoryRows}
        />
      </div>
    </>
  );
}
