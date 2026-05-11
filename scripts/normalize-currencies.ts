import { neon } from "@neondatabase/serverless";

const url = process.env.DATABASE_URL;
if (!url) throw new Error("DATABASE_URL required");
const sql = neon(url);

async function main() {
  const before = (await sql`
    select id, name, institution, currency
    from accounts
    where currency = 'XXX' or currency !~ '^[A-Z]{3}$'
  `) as Array<{ id: string; name: string; institution: string; currency: string }>;

  console.log(`Found ${before.length} accounts with invalid currency:`);
  for (const a of before) {
    console.log(`  ${a.id}  ${a.name} (${a.institution})  currency="${a.currency}"`);
  }
  if (before.length === 0) {
    console.log("Nothing to fix.");
    return;
  }

  const res = (await sql`
    update accounts
    set currency = 'EUR'
    where currency = 'XXX' or currency !~ '^[A-Z]{3}$'
    returning id
  `) as Array<{ id: string }>;
  console.log(`Updated ${res.length} rows to EUR.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
