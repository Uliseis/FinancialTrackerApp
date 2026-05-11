CREATE TABLE "transfer_routes" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"pattern" text NOT NULL,
	"field" text DEFAULT 'description' NOT NULL,
	"match_type" text DEFAULT 'contains' NOT NULL,
	"source_account_id" uuid,
	"target_account_id" uuid NOT NULL,
	"direction" "tx_direction",
	"priority" integer DEFAULT 0 NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "routed_from_tx_id" uuid;--> statement-breakpoint
ALTER TABLE "transfer_routes" ADD CONSTRAINT "transfer_routes_source_account_id_accounts_id_fk" FOREIGN KEY ("source_account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transfer_routes" ADD CONSTRAINT "transfer_routes_target_account_id_accounts_id_fk" FOREIGN KEY ("target_account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "transfer_routes_enabled_priority_idx" ON "transfer_routes" USING btree ("enabled","priority");--> statement-breakpoint
CREATE INDEX "transfer_routes_target_idx" ON "transfer_routes" USING btree ("target_account_id");--> statement-breakpoint
CREATE INDEX "transfer_routes_source_idx" ON "transfer_routes" USING btree ("source_account_id");--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_routed_from_tx_id_transactions_id_fk" FOREIGN KEY ("routed_from_tx_id") REFERENCES "public"."transactions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "transactions_routed_from_idx" ON "transactions" USING btree ("routed_from_tx_id");