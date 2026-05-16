CREATE TABLE "portfolio_valuations" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"account_id" uuid NOT NULL,
	"as_of" timestamp with time zone NOT NULL,
	"market_value_eur" numeric(14, 2) NOT NULL,
	"notes" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "portfolio_valuations" ADD CONSTRAINT "portfolio_valuations_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "portfolio_valuations_account_as_of_idx" ON "portfolio_valuations" USING btree ("account_id","as_of");--> statement-breakpoint
CREATE INDEX "portfolio_valuations_account_idx" ON "portfolio_valuations" USING btree ("account_id");