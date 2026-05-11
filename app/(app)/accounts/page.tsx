import { asc } from "drizzle-orm";
import { db } from "@/lib/db";
import { accountGroups, accounts } from "@/db/schema";
import { PageHeader } from "@/components/page-header";
import { AccountsManager } from "./accounts-manager";

export const dynamic = "force-dynamic";

export default async function AccountsPage() {
  const [acctRows, groupRows] = await Promise.all([
    db.select().from(accounts).orderBy(asc(accounts.name)),
    db.select().from(accountGroups).orderBy(asc(accountGroups.sortOrder)),
  ]);

  return (
    <>
      <PageHeader
        title="Accounts"
        description="Group accounts to roll up balances on the dashboard."
      />
      <div className="p-6">
        <AccountsManager accounts={acctRows} groups={groupRows} />
      </div>
    </>
  );
}
