import { and, asc, eq, inArray, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  accountGroups,
  accounts,
  portfolioValuations,
  type Account,
  type AccountGroup,
  type PortfolioValuation,
} from "@/db/schema";
import { accountInSpaceClause } from "@/lib/spaces";

export interface InvestmentAccountRow {
  account: Account;
  group: AccountGroup;
}

// Intentionally ignores accounts.excluded: investment accounts are typically
// excluded from cash net worth, but they must still appear on /investments.
export async function listInvestmentAccountsInSpace(
  spaceId: string,
  defaultSpaceId: string,
): Promise<InvestmentAccountRow[]> {
  return db
    .select({ account: accounts, group: accountGroups })
    .from(accounts)
    .innerJoin(accountGroups, eq(accounts.groupId, accountGroups.id))
    .where(
      and(
        accountInSpaceClause(spaceId, defaultSpaceId),
        eq(accounts.archived, false),
        eq(accountGroups.kind, "investment"),
      ),
    );
}

export async function listValuationsForAccounts(
  accountIds: string[],
): Promise<PortfolioValuation[]> {
  if (accountIds.length === 0) return [];
  return db
    .select()
    .from(portfolioValuations)
    .where(inArray(portfolioValuations.accountId, accountIds))
    .orderBy(asc(portfolioValuations.asOf));
}

export interface NetContributionLeg {
  accountId: string;
  bookedAt: Date;
  netEur: number;
}

/**
 * All transfer legs into the given investment accounts that count toward "Invested",
 * i.e. where the sibling leg lives outside the investment-group set (we drop
 * inter-investment transfers per the same-class-net-zero rule). Each leg is
 * signed: credits positive, debits negative.
 *
 * Inter-investment exclusion requires an OPPOSITE-direction sibling tx with the
 * same `transfer_group_id` to live in an investment-kind group. This avoids
 * dropping a real cash→broker contribution that happens to share a group id
 * with a multi-leg fan-out.
 */
export async function listInvestmentContributionLegs(
  investmentAccountIds: string[],
): Promise<NetContributionLeg[]> {
  if (investmentAccountIds.length === 0) return [];
  const rows = await db.execute(sql`
    select
      t.account_id as account_id,
      t.booked_at as booked_at,
      case when t.direction = 'credit' then t.amount_eur else -t.amount_eur end as net_eur
    from transactions t
    where t.account_id = any(${investmentAccountIds}::uuid[])
      and t.is_transfer = true
      and t.transfer_group_id is not null
      and t.amount_eur is not null
      and not exists (
        select 1
        from transactions sibling
        join accounts sib_acct on sib_acct.id = sibling.account_id
        join account_groups sib_grp on sib_grp.id = sib_acct.group_id
        where sibling.transfer_group_id = t.transfer_group_id
          and sibling.id <> t.id
          and sibling.direction <> t.direction
          and sib_grp.kind = 'investment'
      )
    order by t.booked_at asc
  `);
  return (rows.rows as Array<{ account_id: string; booked_at: Date; net_eur: string }>).map(
    (r) => ({
      accountId: r.account_id,
      bookedAt: r.booked_at instanceof Date ? r.booked_at : new Date(r.booked_at),
      netEur: Number(r.net_eur),
    }),
  );
}

export interface AccountMetrics {
  accountId: string;
  baselineAsOf: Date | null;
  baselineEur: number | null;
  latestAsOf: Date | null;
  latestEur: number | null;
  netContributionsSinceBaselineEur: number;
  costBasisEur: number | null;
  pnlEur: number | null;
  pnlPct: number | null;
}

function emptyMetrics(accountId: string): AccountMetrics {
  return {
    accountId,
    baselineAsOf: null,
    baselineEur: null,
    latestAsOf: null,
    latestEur: null,
    netContributionsSinceBaselineEur: 0,
    costBasisEur: null,
    pnlEur: null,
    pnlPct: null,
  };
}

/**
 * Per-account metrics: baseline (earliest valuation), current value (latest valuation),
 * cost basis (baseline + net contributions after baseline date), P&L.
 */
export function computeAccountMetrics(
  investmentAccountIds: string[],
  valuations: PortfolioValuation[],
  legs: NetContributionLeg[],
): Map<string, AccountMetrics> {
  const valsByAccount = new Map<string, PortfolioValuation[]>();
  for (const v of valuations) {
    const arr = valsByAccount.get(v.accountId) ?? [];
    arr.push(v);
    valsByAccount.set(v.accountId, arr);
  }

  const out = new Map<string, AccountMetrics>();
  for (const accId of investmentAccountIds) {
    const list = valsByAccount.get(accId) ?? [];
    if (list.length === 0) {
      out.set(accId, emptyMetrics(accId));
      continue;
    }
    const baseline = list[0];
    const latest = list.at(-1)!;
    const baselineTime = baseline.asOf.getTime();
    let net = 0;
    for (const leg of legs) {
      if (leg.accountId !== accId) continue;
      if (leg.bookedAt.getTime() > baselineTime) net += leg.netEur;
    }
    const baselineEur = Number(baseline.marketValueEur);
    const latestEur = Number(latest.marketValueEur);
    const costBasis = baselineEur + net;
    const pnl = latestEur - costBasis;
    const pnlPct = Math.abs(costBasis) > 1e-6 ? pnl / costBasis : null;
    out.set(accId, {
      accountId: accId,
      baselineAsOf: baseline.asOf,
      baselineEur,
      latestAsOf: latest.asOf,
      latestEur,
      netContributionsSinceBaselineEur: net,
      costBasisEur: costBasis,
      pnlEur: pnl,
      pnlPct,
    });
  }
  return out;
}

export interface PortfolioSeriesPoint {
  date: string; // YYYY-MM-DD
  marketValueEur: number;
  costBasisEur: number;
}

/**
 * Time series with one point per distinct valuation date across all accounts.
 * Per account at date d:
 *   marketValue = latest valuation with asOf <= d (carry-forward)
 *   costBasis   = baselineEur + sum(legs.netEur where bookedAt in (baselineDate, d])
 * Sums across accounts.
 */
export function computePortfolioSeries(
  investmentAccountIds: string[],
  valuations: PortfolioValuation[],
  legs: NetContributionLeg[],
): PortfolioSeriesPoint[] {
  if (valuations.length === 0) return [];

  const valsByAccount = new Map<string, PortfolioValuation[]>();
  for (const v of valuations) {
    const arr = valsByAccount.get(v.accountId) ?? [];
    arr.push(v);
    valsByAccount.set(v.accountId, arr);
  }

  const dateSet = new Set<string>();
  for (const v of valuations) dateSet.add(v.asOf.toISOString().slice(0, 10));
  const dates = Array.from(dateSet).sort((a, b) => a.localeCompare(b));

  const series: PortfolioSeriesPoint[] = [];
  for (const d of dates) {
    const endTime = new Date(d + "T23:59:59.999Z").getTime();
    let marketValue = 0;
    let costBasis = 0;
    for (const accId of investmentAccountIds) {
      const list = valsByAccount.get(accId);
      if (!list || list.length === 0) continue;
      const baseline = list[0];
      const baselineTime = baseline.asOf.getTime();
      if (baselineTime > endTime) continue;
      let mv = 0;
      for (const v of list) {
        if (v.asOf.getTime() <= endTime) mv = Number(v.marketValueEur);
        else break;
      }
      marketValue += mv;
      let contrib = 0;
      for (const leg of legs) {
        if (leg.accountId !== accId) continue;
        const t = leg.bookedAt.getTime();
        if (t > baselineTime && t <= endTime) contrib += leg.netEur;
      }
      costBasis += Number(baseline.marketValueEur) + contrib;
    }
    series.push({ date: d, marketValueEur: marketValue, costBasisEur: costBasis });
  }

  return series;
}

/**
 * Sum of latest valuations across the given investment accounts (EUR).
 * Used by the dashboard to compute Total Net Worth = cash + investments.
 */
export async function sumLatestInvestmentValueEur(
  investmentAccountIds: string[],
): Promise<number> {
  if (investmentAccountIds.length === 0) return 0;
  const rows = await db.execute(sql`
    select coalesce(sum(market_value_eur), 0) as total
    from (
      select distinct on (account_id) account_id, market_value_eur
      from portfolio_valuations
      where account_id = any(${investmentAccountIds}::uuid[])
      order by account_id, as_of desc
    ) latest
  `);
  return Number((rows.rows[0] as { total: string } | undefined)?.total ?? 0);
}

/**
 * Account ids in the space whose group has kind='investment'. Used to feed the
 * dashboard's Total Net Worth computation.
 */
export async function listInvestmentAccountIdsInSpace(
  spaceId: string,
  defaultSpaceId: string,
): Promise<string[]> {
  const rows = await db
    .select({ id: accounts.id })
    .from(accounts)
    .innerJoin(accountGroups, eq(accounts.groupId, accountGroups.id))
    .where(
      and(
        accountInSpaceClause(spaceId, defaultSpaceId),
        eq(accounts.archived, false),
        eq(accountGroups.kind, "investment"),
      ),
    );
  return rows.map((r) => r.id);
}

export type InvestmentPeriod = "ytd" | "1y" | "3y" | "all";

export function periodStartDate(period: InvestmentPeriod, now = new Date()): Date | null {
  if (period === "all") return null;
  if (period === "ytd") return new Date(Date.UTC(now.getUTCFullYear(), 0, 1));
  if (period === "1y") {
    const d = new Date(now);
    d.setUTCFullYear(d.getUTCFullYear() - 1);
    return d;
  }
  const d = new Date(now);
  d.setUTCFullYear(d.getUTCFullYear() - 3);
  return d;
}
