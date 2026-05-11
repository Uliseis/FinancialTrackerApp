import { asc } from "drizzle-orm";
import { db } from "@/lib/db";
import { accountGroups, accounts } from "@/db/schema";
import { PageHeader } from "@/components/page-header";
import {
  computeAccountBalancesEur,
  computeManualAccountNativeBalances,
  isManualAccount,
} from "@/lib/accounts";
import { getRate } from "@/lib/fx";
import { AccountsManager } from "./accounts-manager";

export const dynamic = "force-dynamic";

export default async function AccountsPage() {
  const [acctRows, groupRows] = await Promise.all([
    db.select().from(accounts).orderBy(asc(accounts.name)),
    db.select().from(accountGroups).orderBy(asc(accountGroups.sortOrder)),
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
  const [eurMap, manualNativeMap] = await Promise.all([
    computeAccountBalancesEur(activeRows, { rateFor }),
    computeManualAccountNativeBalances(activeRows),
  ]);

  const nativeBalances: Record<string, string | null> = {};
  for (const a of acctRows) {
    if (isManualAccount(a)) {
      const v = manualNativeMap.get(a.id);
      nativeBalances[a.id] = v != null ? v.toFixed(2) : a.balance;
    } else {
      nativeBalances[a.id] = a.balance;
    }
  }
  const eurBalances: Record<string, number> = {};
  for (const [id, v] of eurMap) eurBalances[id] = v;

  return (
    <>
      <PageHeader
        title="Accounts"
        description="Group accounts to roll up balances on the dashboard."
      />
      <div className="p-6">
        <AccountsManager
          accounts={acctRows}
          groups={groupRows}
          nativeBalances={nativeBalances}
          eurBalances={eurBalances}
        />
      </div>
    </>
  );
}
