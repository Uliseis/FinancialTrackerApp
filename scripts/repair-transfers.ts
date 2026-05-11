import { repairTransferGroups } from "@/lib/transfers";

async function main() {
  if (!process.env.DATABASE_URL) throw new Error("DATABASE_URL required");
  const before = await repairTransferGroups();
  console.log("Repair result:", before);
  const after = await repairTransferGroups();
  console.log("Second run (should all be zeros):", after);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
