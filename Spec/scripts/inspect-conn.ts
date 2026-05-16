import { drizzle } from "drizzle-orm/neon-http";
import { neon } from "@neondatabase/serverless";
import { desc } from "drizzle-orm";
import { connections, syncRuns } from "../db/schema";

async function main() {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is required");
  const sql = neon(url);
  const db = drizzle({ client: sql });

  const rows = await db.select().from(connections).orderBy(desc(connections.createdAt));
  for (const r of rows) {
    console.log("---");
    console.log("id:           ", r.id);
    console.log("connector:    ", r.connector);
    console.log("institution:  ", r.institutionName ?? r.institutionId);
    console.log("status:       ", r.status);
    console.log("sessionId:    ", r.sessionId);
    console.log("expiresAt:    ", r.expiresAt?.toISOString() ?? "—");
    console.log("lastSyncAt:   ", r.lastSyncAt?.toISOString() ?? "—");
    console.log("lastError:    ", r.lastError);
    console.log("metadata:     ", JSON.stringify(r.metadata, null, 2));
  }

  console.log("\n=== recent sync runs ===");
  const runs = await db.select().from(syncRuns).orderBy(desc(syncRuns.startedAt)).limit(5);
  for (const r of runs) {
    console.log("---");
    console.log("id:                  ", r.id);
    console.log("connectionId:        ", r.connectionId);
    console.log("status:              ", r.status);
    console.log("insertedTransactions:", r.insertedTransactions);
    console.log("error:               ", r.error);
    console.log("startedAt:           ", r.startedAt.toISOString());
    console.log("finishedAt:          ", r.finishedAt?.toISOString() ?? "—");
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
