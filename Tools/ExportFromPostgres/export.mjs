#!/usr/bin/env node
// Reads the live Neon Postgres and writes a JSON dump matching DumpDocument
// in Tools/ImportFromPostgres. One-shot at cutover.
//
// Usage:
//   DATABASE_URL=postgres://... node export.mjs > dump.json
//
// Skips instruments / holdings / prices (dropped per locked decision).
// Synthesizes transfer_groups rows from DISTINCT transactions.transfer_group_id
// with paired_at = MIN(booked_at) and route_id = MAX(raw->>'routeId') across members.
// Denormalizes raw.routeId onto each transaction row.

import { neon } from "@neondatabase/serverless";

const SCHEMA_VERSION = 1;

if (!process.env.DATABASE_URL) {
  console.error("DATABASE_URL is not set");
  process.exit(2);
}

const sql = neon(process.env.DATABASE_URL);

function toISO(v) {
  if (v == null) return null;
  if (v instanceof Date) return v.toISOString();
  return new Date(v).toISOString();
}

function toDate(v) {
  if (v == null) return null;
  if (v instanceof Date) {
    const y = v.getUTCFullYear();
    const m = String(v.getUTCMonth() + 1).padStart(2, "0");
    const d = String(v.getUTCDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  }
  return String(v).slice(0, 10);
}

function toDecimal(v) {
  if (v == null) return null;
  return String(v);
}

function toJSON(v) {
  if (v == null) return null;
  if (typeof v === "string") {
    try { return JSON.parse(v); } catch { return null; }
  }
  return v;
}

async function exportConnections() {
  const rows = await sql`SELECT * FROM connections ORDER BY created_at`;
  return rows.map((r) => ({
    id: r.id,
    connector: r.connector,
    institutionId: r.institution_id,
    institutionName: r.institution_name,
    sessionId: r.session_id,
    accessTokenEnc: r.access_token_enc,
    refreshTokenEnc: r.refresh_token_enc,
    metadata: toJSON(r.metadata),
    status: r.status,
    expiresAt: toISO(r.expires_at),
    lastSyncAt: toISO(r.last_sync_at),
    lastError: r.last_error,
    createdAt: toISO(r.created_at),
    updatedAt: toISO(r.updated_at),
  }));
}

async function exportAccountGroups() {
  const rows = await sql`SELECT * FROM account_groups ORDER BY sort_order`;
  return rows.map((r) => ({
    id: r.id,
    name: r.name,
    color: r.color,
    kind: r.kind,
    sortOrder: r.sort_order,
    createdAt: toISO(r.created_at),
    updatedAt: toISO(r.updated_at),
  }));
}

async function exportAccountSpaces() {
  const rows = await sql`SELECT * FROM account_spaces ORDER BY sort_order`;
  return rows.map((r) => ({
    id: r.id,
    name: r.name,
    color: r.color,
    isDefault: r.is_default,
    sortOrder: r.sort_order,
    createdAt: toISO(r.created_at),
    updatedAt: toISO(r.updated_at),
  }));
}

async function exportAccounts() {
  const rows = await sql`SELECT * FROM accounts ORDER BY created_at`;
  return rows.map((r) => ({
    id: r.id,
    connectionId: r.connection_id,
    groupId: r.group_id,
    spaceId: r.space_id,
    externalId: r.external_id,
    type: r.type,
    institution: r.institution,
    name: r.name,
    currency: r.currency,
    iban: r.iban,
    balance: toDecimal(r.balance),
    balanceUpdatedAt: toISO(r.balance_updated_at),
    metadata: toJSON(r.metadata),
    archived: r.archived,
    excluded: r.excluded,
    manualOpeningBalance: toDecimal(r.manual_opening_balance),
    balanceAnchor: toDecimal(r.balance_anchor),
    balanceAnchorAt: toISO(r.balance_anchor_at),
    createdAt: toISO(r.created_at),
  }));
}

async function exportCategories() {
  const rows = await sql`SELECT * FROM categories ORDER BY created_at`;
  return rows.map((r) => ({
    id: r.id,
    name: r.name,
    parentId: r.parent_id,
    kind: r.kind,
    color: r.color,
    createdAt: toISO(r.created_at),
  }));
}

async function exportCategoryRules() {
  const rows = await sql`SELECT * FROM category_rules ORDER BY priority DESC, created_at`;
  return rows.map((r) => ({
    id: r.id,
    pattern: r.pattern,
    field: r.field,
    matchType: r.match_type,
    categoryId: r.category_id,
    priority: r.priority,
    createdAt: toISO(r.created_at),
  }));
}

async function exportTransferRoutes() {
  const rows = await sql`SELECT * FROM transfer_routes ORDER BY priority DESC, created_at`;
  return rows.map((r) => ({
    id: r.id,
    pattern: r.pattern,
    field: r.field,
    matchType: r.match_type,
    sourceAccountId: r.source_account_id,
    targetAccountId: r.target_account_id,
    direction: r.direction,
    priority: r.priority,
    enabled: r.enabled,
    createdAt: toISO(r.created_at),
    updatedAt: toISO(r.updated_at),
  }));
}

async function exportBudgets() {
  const rows = await sql`SELECT * FROM budgets ORDER BY created_at`;
  return rows.map((r) => ({
    id: r.id,
    categoryId: r.category_id,
    amountEur: toDecimal(r.amount_eur),
    period: r.period,
    startsOn: toDate(r.starts_on),
    active: r.active,
    createdAt: toISO(r.created_at),
    updatedAt: toISO(r.updated_at),
  }));
}

async function exportFxRates() {
  const rows = await sql`SELECT * FROM fx_rates ORDER BY date, currency`;
  return rows.map((r) => ({
    id: r.id,
    date: toDate(r.date),
    currency: r.currency,
    rate: toDecimal(r.rate),
    createdAt: toISO(r.created_at),
  }));
}

async function exportTransferGroups() {
  const rows = await sql`
    SELECT
      transfer_group_id AS id,
      MIN(booked_at) AS paired_at,
      MAX(raw->>'routeId') AS route_id,
      MIN(created_at) AS created_at
    FROM transactions
    WHERE transfer_group_id IS NOT NULL
    GROUP BY transfer_group_id
  `;
  return rows.map((r) => ({
    id: r.id,
    pairedAt: toISO(r.paired_at),
    routeId: r.route_id,
    createdAt: toISO(r.created_at),
  }));
}

async function exportTransactions() {
  const rows = await sql`
    SELECT *, raw->>'routeId' AS route_id_extracted
    FROM transactions
    ORDER BY booked_at
  `;
  return rows.map((r) => ({
    id: r.id,
    accountId: r.account_id,
    externalId: r.external_id,
    bookedAt: toISO(r.booked_at),
    valueAt: toISO(r.value_at),
    amount: toDecimal(r.amount),
    currency: r.currency,
    amountEur: toDecimal(r.amount_eur),
    fxRateUsed: toDecimal(r.fx_rate_used),
    direction: r.direction,
    description: r.description,
    counterparty: r.counterparty,
    categoryId: r.category_id,
    categorySource: r.category_source,
    isTransfer: r.is_transfer,
    transferGroupId: r.transfer_group_id,
    routedFromTxId: r.routed_from_tx_id,
    routeId: r.route_id_extracted,
    sharedExpenseGroupId: r.shared_expense_group_id,
    raw: toJSON(r.raw),
    createdAt: toISO(r.created_at),
  }));
}

async function exportSharedExpenseGroups() {
  const rows = await sql`SELECT * FROM shared_expense_groups ORDER BY created_at`;
  return rows.map((r) => ({
    id: r.id,
    label: r.label,
    primaryTxId: r.primary_tx_id,
    attributionMonth: toDate(r.attribution_month),
    createdAt: toISO(r.created_at),
    updatedAt: toISO(r.updated_at),
  }));
}

async function exportPortfolioValuations() {
  const rows = await sql`SELECT * FROM portfolio_valuations ORDER BY as_of`;
  return rows.map((r) => ({
    id: r.id,
    accountId: r.account_id,
    asOf: toISO(r.as_of),
    marketValueEur: toDecimal(r.market_value_eur),
    cashValueEur: toDecimal(r.cash_value_eur),
    notes: r.notes,
    createdAt: toISO(r.created_at),
    updatedAt: toISO(r.updated_at),
  }));
}

async function exportSyncRuns() {
  const rows = await sql`SELECT * FROM sync_runs ORDER BY started_at`;
  return rows.map((r) => ({
    id: r.id,
    connector: r.connector,
    connectionId: r.connection_id,
    startedAt: toISO(r.started_at),
    finishedAt: toISO(r.finished_at),
    status: r.status,
    insertedTransactions: r.inserted_transactions,
    error: r.error,
    raw: toJSON(r.raw),
  }));
}

async function main() {
  const [
    connections,
    accountGroups,
    accountSpaces,
    accounts,
    categories,
    categoryRules,
    transferRoutes,
    budgets,
    fxRates,
    transferGroups,
    transactions,
    sharedExpenseGroups,
    portfolioValuations,
    syncRuns,
  ] = await Promise.all([
    exportConnections(),
    exportAccountGroups(),
    exportAccountSpaces(),
    exportAccounts(),
    exportCategories(),
    exportCategoryRules(),
    exportTransferRoutes(),
    exportBudgets(),
    exportFxRates(),
    exportTransferGroups(),
    exportTransactions(),
    exportSharedExpenseGroups(),
    exportPortfolioValuations(),
    exportSyncRuns(),
  ]);

  const doc = {
    exportedAt: new Date().toISOString(),
    schemaVersion: SCHEMA_VERSION,
    connections,
    accountGroups,
    accountSpaces,
    accounts,
    categories,
    categoryRules,
    transferRoutes,
    budgets,
    fxRates,
    transferGroups,
    transactions,
    sharedExpenseGroups,
    portfolioValuations,
    syncRuns,
  };

  process.stdout.write(JSON.stringify(doc, null, 2));
  process.stdout.write("\n");

  const counts = Object.fromEntries(
    Object.entries(doc)
      .filter(([k]) => Array.isArray(doc[k]))
      .map(([k, v]) => [k, v.length])
  );
  console.error(`exported (counts): ${JSON.stringify(counts)}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
