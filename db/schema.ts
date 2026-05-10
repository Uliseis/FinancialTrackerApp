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

export const accounts = pgTable(
  "accounts",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    connectionId: uuid("connection_id").references(() => connections.id, {
      onDelete: "cascade",
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
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    externalIdx: uniqueIndex("accounts_connector_external_idx").on(
      t.connectionId,
      t.externalId,
    ),
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

export const categories = pgTable("categories", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  parentId: uuid("parent_id"),
  kind: text("kind").notNull().default("expense"),
  color: text("color"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

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
    direction: txDirectionEnum("direction").notNull(),
    description: text("description"),
    counterparty: text("counterparty"),
    categoryId: uuid("category_id").references(() => categories.id, {
      onDelete: "set null",
    }),
    raw: jsonb("raw").$type<Record<string, unknown>>(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => ({
    externalIdx: uniqueIndex("transactions_account_external_idx").on(
      t.accountId,
      t.externalId,
    ),
    bookedIdx: index("transactions_booked_idx").on(t.bookedAt),
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
export type Transaction = typeof transactions.$inferSelect;
export type NewTransaction = typeof transactions.$inferInsert;
export type Instrument = typeof instruments.$inferSelect;
export type Holding = typeof holdings.$inferSelect;
export type Category = typeof categories.$inferSelect;
export type CategoryRule = typeof categoryRules.$inferSelect;
export type SyncRun = typeof syncRuns.$inferSelect;

// Quiet unused-import warning if `sql` ends up unused in builds.
export const _sql = sql;
