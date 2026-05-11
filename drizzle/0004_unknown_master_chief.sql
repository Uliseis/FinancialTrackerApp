CREATE TABLE "account_spaces" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"color" text,
	"is_default" boolean DEFAULT false NOT NULL,
	"sort_order" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "accounts" ADD COLUMN "excluded" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "accounts" ADD COLUMN "space_id" uuid;--> statement-breakpoint
ALTER TABLE "accounts" ADD COLUMN "balance_anchor" numeric(20, 4);--> statement-breakpoint
ALTER TABLE "accounts" ADD COLUMN "balance_anchor_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "accounts" ADD CONSTRAINT "accounts_space_id_account_spaces_id_fk" FOREIGN KEY ("space_id") REFERENCES "public"."account_spaces"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "accounts_space_idx" ON "accounts" USING btree ("space_id");