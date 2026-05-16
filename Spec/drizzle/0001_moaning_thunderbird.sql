CREATE TYPE "public"."account_group_kind" AS ENUM('cash', 'savings', 'investment', 'credit', 'other');--> statement-breakpoint
CREATE TYPE "public"."budget_period" AS ENUM('week', 'month', 'year');--> statement-breakpoint
CREATE TYPE "public"."category_source" AS ENUM('bank', 'rule', 'manual');--> statement-breakpoint
CREATE TABLE "account_groups" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"color" text,
	"kind" "account_group_kind" DEFAULT 'other' NOT NULL,
	"sort_order" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "budgets" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"category_id" uuid NOT NULL,
	"amount_eur" numeric(14, 2) NOT NULL,
	"period" "budget_period" DEFAULT 'month' NOT NULL,
	"starts_on" date NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "fx_rates" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"date" date NOT NULL,
	"currency" text NOT NULL,
	"rate" numeric(18, 8) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "accounts" ADD COLUMN "group_id" uuid;--> statement-breakpoint
ALTER TABLE "accounts" ADD COLUMN "manual_opening_balance" numeric(20, 4);--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "amount_eur" numeric(14, 2);--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "fx_rate_used" numeric(18, 8);--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "category_source" "category_source";--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "is_transfer" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "transfer_group_id" uuid;--> statement-breakpoint
ALTER TABLE "budgets" ADD CONSTRAINT "budgets_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "fx_rates_date_currency_idx" ON "fx_rates" USING btree ("date","currency");--> statement-breakpoint
ALTER TABLE "accounts" ADD CONSTRAINT "accounts_group_id_account_groups_id_fk" FOREIGN KEY ("group_id") REFERENCES "public"."account_groups"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "accounts_group_idx" ON "accounts" USING btree ("group_id");--> statement-breakpoint
CREATE INDEX "transactions_transfer_idx" ON "transactions" USING btree ("is_transfer");--> statement-breakpoint
CREATE INDEX "transactions_transfer_group_idx" ON "transactions" USING btree ("transfer_group_id");--> statement-breakpoint
CREATE INDEX "transactions_category_idx" ON "transactions" USING btree ("category_id");--> statement-breakpoint
INSERT INTO "categories" ("name", "kind", "color")
SELECT * FROM (VALUES
  ('Groceries', 'expense', '#10b981'),
  ('Restaurants', 'expense', '#f97316'),
  ('Transport', 'expense', '#3b82f6'),
  ('Housing', 'expense', '#a855f7'),
  ('Utilities', 'expense', '#06b6d4'),
  ('Subscriptions', 'expense', '#8b5cf6'),
  ('Entertainment', 'expense', '#ec4899'),
  ('Health', 'expense', '#ef4444'),
  ('Shopping', 'expense', '#eab308'),
  ('Travel', 'expense', '#14b8a6'),
  ('Fees', 'expense', '#94a3b8'),
  ('Salary', 'income', '#22c55e'),
  ('Other Income', 'income', '#84cc16'),
  ('Uncategorized', 'expense', '#64748b')
) AS v(name, kind, color)
WHERE NOT EXISTS (SELECT 1 FROM "categories");