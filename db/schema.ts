import { sql } from "drizzle-orm";
import {
  pgTable,
  text,
  timestamp,
  numeric,
  jsonb,
  integer,
  boolean,
  uniqueIndex,
  index,
  pgEnum,
  uuid,
  date,
  type AnyPgColumn,
} from "drizzle-orm/pg-core";

export const accountTypeEnum = pgEnum("account_type", ["bank", "broker", "crypto"]);
export const connectionStatusEnum = pgEnum("connection_status", [
  "pending",
  "active",
  "expired",
  "error",
  "revoked",
]);
export const connectorEnum = pgEnum("connector", [
  "enablebanking",
  "trading212",
  "revolutx",
  "manual",
]);
export const txDirectionEnum = pgEnum("tx_direction", ["debit", "credit"]);
export const instrumentTypeEnum = pgEnum("instrument_type", [
  "equity",
  "etf",
  "crypto",
  "fund",
  "cash",
  "other",
]);
export const accountGroupKindEnum = pgEnum("account_group_kind", [
  "cash",
  "savings",
  "investment",
  "credit",
  "other",
]);
export const budgetPeriodEnum = pgEnum("budget_period", ["week", "month", "year"]);
export const categorySourceEnum = pgEnum("category_source", ["bank", "rule", "manual"]);

export const connections = pgTable(
  "connections",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    connector: connectorEnum("connector").notNull(),
    institutionId: text("institution_id"),
    institutionName: text("institution_name"),
    sessionId: text("session_id"),
    accessTokenEnc: text("access_token_enc"),
    refreshTokenEnc: text("refresh_token_enc"),
    metadata: jsonb("metadata").$type<Record<string, unknown>>(),
    status: connectionStatusEnum("status").notNull().default("pending"),
    expiresAt: timestamp("expires_at", { withTimezone: true }),
    lastSyncAt: timestamp("last_sync_at", { withTimezone: true }),
    lastError: text("last_error"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    statusIdx: index("connections_status_idx").on(t.status),
  }),
);

export const accountGroups = pgTable("account_groups", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  color: text("color"),
  kind: accountGroupKindEnum("kind").notNull().default("other"),
  sortOrder: integer("sort_order").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const accounts = pgTable(
  "accounts",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    connectionId: uuid("connection_id").references(() => connections.id, {
      onDelete: "cascade",
    }),
    groupId: uuid("group_id").references(() => accountGroups.id, {
      onDelete: "set null",
    }),
    externalId: text("external_id").notNull(),
    type: accountTypeEnum("type").notNull(),
    institution: text("institution").notNull(),
    name: text("name").notNull(),
    currency: text("currency").notNull(),
    iban: text("iban"),
    balance: numeric("balance", { precision: 20, scale: 4 }),
    balanceUpdatedAt: timestamp("balance_updated_at", { withTimezone: true }),
    metadata: jsonb("metadata").$type<Record<string, unknown>>(),
    archived: boolean("archived").notNull().default(false),
    manualOpeningBalance: numeric("manual_opening_balance", { precision: 20, scale: 4 }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    externalIdx: uniqueIndex("accounts_connector_external_idx").on(
      t.connectionId,
      t.externalId,
    ),
    groupIdx: index("accounts_group_idx").on(t.groupId),
  }),
);

export const instruments = pgTable(
  "instruments",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    symbol: text("symbol").notNull(),
    isin: text("isin"),
    name: text("name").notNull(),
    type: instrumentTypeEnum("type").notNull(),
    currency: text("currency").notNull(),
    metadata: jsonb("metadata").$type<Record<string, unknown>>(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    symbolIdx: uniqueIndex("instruments_symbol_idx").on(t.symbol),
  }),
);

export const categories = pgTable(
  "categories",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    name: text("name").notNull(),
    parentId: uuid("parent_id"),
    kind: text("kind").notNull().default("expense"),
    color: text("color"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    kindIdx: index("categories_kind_idx").on(t.kind),
  }),
);

export const categoryRules = pgTable("category_rules", {
  id: uuid("id").primaryKey().defaultRandom(),
  pattern: text("pattern").notNull(),
  field: text("field").notNull().default("description"),
  matchType: text("match_type").notNull().default("contains"),
  categoryId: uuid("category_id")
    .notNull()
    .references(() => categories.id, { onDelete: "cascade" }),
  priority: integer("priority").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const transferRoutes = pgTable(
  "transfer_routes",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    pattern: text("pattern").notNull(),
    field: text("field").notNull().default("description"),
    matchType: text("match_type").notNull().default("contains"),
    sourceAccountId: uuid("source_account_id").references(() => accounts.id, {
      onDelete: "cascade",
    }),
    targetAccountId: uuid("target_account_id")
      .notNull()
      .references(() => accounts.id, { onDelete: "cascade" }),
    direction: txDirectionEnum("direction"),
    priority: integer("priority").notNull().default(0),
    enabled: boolean("enabled").notNull().default(true),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    enabledPriorityIdx: index("transfer_routes_enabled_priority_idx").on(
      t.enabled,
      t.priority,
    ),
    targetIdx: index("transfer_routes_target_idx").on(t.targetAccountId),
    sourceIdx: index("transfer_routes_source_idx").on(t.sourceAccountId),
  }),
);

export const budgets = pgTable("budgets", {
  id: uuid("id").primaryKey().defaultRandom(),
  categoryId: uuid("category_id")
    .notNull()
    .references(() => categories.id, { onDelete: "cascade" }),
  amountEur: numeric("amount_eur", { precision: 14, scale: 2 }).notNull(),
  period: budgetPeriodEnum("period").notNull().default("month"),
  startsOn: date("starts_on").notNull(),
  active: boolean("active").notNull().default(true),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const fxRates = pgTable(
  "fx_rates",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    date: date("date").notNull(),
    currency: text("currency").notNull(),
    rate: numeric("rate", { precision: 18, scale: 8 }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    dateCcyIdx: uniqueIndex("fx_rates_date_currency_idx").on(t.date, t.currency),
  }),
);

export const transactions = pgTable(
  "transactions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    accountId: uuid("account_id")
      .notNull()
      .references(() => accounts.id, { onDelete: "cascade" }),
    externalId: text("external_id").notNull(),
    bookedAt: timestamp("booked_at", { withTimezone: true }).notNull(),
    valueAt: timestamp("value_at", { withTimezone: true }),
    amount: numeric("amount", { precision: 20, scale: 4 }).notNull(),
    currency: text("currency").notNull(),
    amountEur: numeric("amount_eur", { precision: 14, scale: 2 }),
    fxRateUsed: numeric("fx_rate_used", { precision: 18, scale: 8 }),
    direction: txDirectionEnum("direction").notNull(),
    description: text("description"),
    counterparty: text("counterparty"),
    categoryId: uuid("category_id").references(() => categories.id, {
      onDelete: "set null",
    }),
    categorySource: categorySourceEnum("category_source"),
    isTransfer: boolean("is_transfer").notNull().default(false),
    transferGroupId: uuid("transfer_group_id"),
    routedFromTxId: uuid("routed_from_tx_id").references(
      (): AnyPgColumn => transactions.id,
      { onDelete: "cascade" },
    ),
    sharedExpenseGroupId: uuid("shared_expense_group_id").references(
      (): AnyPgColumn => sharedExpenseGroups.id,
      { onDelete: "set null" },
    ),
    raw: jsonb("raw").$type<Record<string, unknown>>(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    externalIdx: uniqueIndex("transactions_account_external_idx").on(
      t.accountId,
      t.externalId,
    ),
    bookedIdx: index("transactions_booked_idx").on(t.bookedAt),
    transferIdx: index("transactions_transfer_idx").on(t.isTransfer),
    transferGroupIdx: index("transactions_transfer_group_idx").on(t.transferGroupId),
    routedFromIdx: index("transactions_routed_from_idx").on(t.routedFromTxId),
    sharedExpenseIdx: index("transactions_shared_expense_idx").on(t.sharedExpenseGroupId),
    categoryIdx: index("transactions_category_idx").on(t.categoryId),
  }),
);

export const sharedExpenseGroups = pgTable(
  "shared_expense_groups",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    label: text("label").notNull(),
    primaryTxId: uuid("primary_tx_id")
      .notNull()
      .references(() => transactions.id, { onDelete: "cascade" }),
    attributionMonth: date("attribution_month").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    primaryIdx: index("shared_expense_groups_primary_idx").on(t.primaryTxId),
    monthIdx: index("shared_expense_groups_month_idx").on(t.attributionMonth),
  }),
);

export const holdings = pgTable(
  "holdings",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    accountId: uuid("account_id")
      .notNull()
      .references(() => accounts.id, { onDelete: "cascade" }),
    instrumentId: uuid("instrument_id")
      .notNull()
      .references(() => instruments.id, { onDelete: "restrict" }),
    quantity: numeric("quantity", { precision: 28, scale: 8 }).notNull(),
    avgCost: numeric("avg_cost", { precision: 20, scale: 6 }),
    avgCostCurrency: text("avg_cost_currency"),
    lastPrice: numeric("last_price", { precision: 20, scale: 6 }),
    lastPriceCurrency: text("last_price_currency"),
    lastPriceAt: timestamp("last_price_at", { withTimezone: true }),
    asOf: timestamp("as_of", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    accountInstrumentIdx: uniqueIndex("holdings_account_instrument_idx").on(
      t.accountId,
      t.instrumentId,
    ),
  }),
);

export const prices = pgTable(
  "prices",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    instrumentId: uuid("instrument_id")
      .notNull()
      .references(() => instruments.id, { onDelete: "cascade" }),
    date: timestamp("date", { withTimezone: true }).notNull(),
    close: numeric("close", { precision: 20, scale: 6 }).notNull(),
    currency: text("currency").notNull(),
  },
  (t) => ({
    instrDateIdx: uniqueIndex("prices_instrument_date_idx").on(t.instrumentId, t.date),
  }),
);

export const syncRuns = pgTable(
  "sync_runs",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    connector: connectorEnum("connector").notNull(),
    connectionId: uuid("connection_id").references(() => connections.id, {
      onDelete: "set null",
    }),
    startedAt: timestamp("started_at", { withTimezone: true }).notNull().defaultNow(),
    finishedAt: timestamp("finished_at", { withTimezone: true }),
    status: text("status").notNull().default("running"),
    insertedTransactions: integer("inserted_transactions").notNull().default(0),
    error: text("error"),
    raw: jsonb("raw").$type<Record<string, unknown>>(),
  },
  (t) => ({
    startedIdx: index("sync_runs_started_idx").on(t.startedAt.desc()),
  }),
);

export type Connection = typeof connections.$inferSelect;
export type NewConnection = typeof connections.$inferInsert;
export type Account = typeof accounts.$inferSelect;
export type NewAccount = typeof accounts.$inferInsert;
export type AccountGroup = typeof accountGroups.$inferSelect;
export type NewAccountGroup = typeof accountGroups.$inferInsert;
export type Transaction = typeof transactions.$inferSelect;
export type NewTransaction = typeof transactions.$inferInsert;
export type Instrument = typeof instruments.$inferSelect;
export type Holding = typeof holdings.$inferSelect;
export type Category = typeof categories.$inferSelect;
export type NewCategory = typeof categories.$inferInsert;
export type CategoryRule = typeof categoryRules.$inferSelect;
export type NewCategoryRule = typeof categoryRules.$inferInsert;
export type TransferRoute = typeof transferRoutes.$inferSelect;
export type NewTransferRoute = typeof transferRoutes.$inferInsert;
export type Budget = typeof budgets.$inferSelect;
export type NewBudget = typeof budgets.$inferInsert;
export type FxRate = typeof fxRates.$inferSelect;
export type NewFxRate = typeof fxRates.$inferInsert;
export type SyncRun = typeof syncRuns.$inferSelect;
export type SharedExpenseGroup = typeof sharedExpenseGroups.$inferSelect;
export type NewSharedExpenseGroup = typeof sharedExpenseGroups.$inferInsert;

// Quiet unused-import warning if `sql` ends up unused in builds.
export const _sql = sql;
