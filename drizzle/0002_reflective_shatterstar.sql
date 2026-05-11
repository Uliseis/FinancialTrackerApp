CREATE TABLE "shared_expense_groups" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"label" text NOT NULL,
	"primary_tx_id" uuid NOT NULL,
	"attribution_month" date NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "shared_expense_group_id" uuid;--> statement-breakpoint
ALTER TABLE "shared_expense_groups" ADD CONSTRAINT "shared_expense_groups_primary_tx_id_transactions_id_fk" FOREIGN KEY ("primary_tx_id") REFERENCES "public"."transactions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "shared_expense_groups_primary_idx" ON "shared_expense_groups" USING btree ("primary_tx_id");--> statement-breakpoint
CREATE INDEX "shared_expense_groups_month_idx" ON "shared_expense_groups" USING btree ("attribution_month");--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_shared_expense_group_id_shared_expense_groups_id_fk" FOREIGN KEY ("shared_expense_group_id") REFERENCES "public"."shared_expense_groups"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "categories_kind_idx" ON "categories" USING btree ("kind");--> statement-breakpoint
CREATE INDEX "transactions_shared_expense_idx" ON "transactions" USING btree ("shared_expense_group_id");