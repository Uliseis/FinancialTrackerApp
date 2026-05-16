import { neon } from "@neondatabase/serverless";

const url = process.env.DATABASE_URL;
if (!url) throw new Error("DATABASE_URL required");
const sql = neon(url);

async function main() {
  const existing = (await sql`
    select id, name from account_spaces where is_default = true limit 1
  `) as Array<{ id: string; name: string }>;

  let defaultId: string;
  if (existing.length > 0) {
    defaultId = existing[0].id;
    console.log(`Default space already exists: ${defaultId} (${existing[0].name})`);
  } else {
    const created = (await sql`
      insert into account_spaces (name, color, is_default, sort_order)
      values ('Individual', '#3b82f6', true, 0)
      returning id
    `) as Array<{ id: string }>;
    defaultId = created[0].id;
    console.log(`Created default 'Individual' space: ${defaultId}`);
  }

  const updated = (await sql`
    update accounts
    set space_id = ${defaultId}
    where space_id is null
    returning id
  `) as Array<{ id: string }>;
  console.log(`Backfilled space_id for ${updated.length} accounts.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
