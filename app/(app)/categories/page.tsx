import { asc, count, desc } from "drizzle-orm";
import { db } from "@/lib/db";
import { categories, categoryRules, transactions } from "@/db/schema";
import { PageHeader } from "@/components/page-header";
import { CategoriesManager } from "./categories-manager";

export const dynamic = "force-dynamic";

export default async function CategoriesPage() {
  const [cats, rules, txByCategory] = await Promise.all([
    db.select().from(categories).orderBy(asc(categories.name)),
    db.select().from(categoryRules).orderBy(desc(categoryRules.priority)),
    db
      .select({ categoryId: transactions.categoryId, total: count() })
      .from(transactions)
      .groupBy(transactions.categoryId),
  ]);

  const usage = new Map<string, number>();
  for (const row of txByCategory) {
    if (row.categoryId) usage.set(row.categoryId, row.total);
  }

  return (
    <>
      <PageHeader
        title="Categories"
        description="Organize your spending. Add rules to auto-tag matching transactions."
      />
      <div className="p-6">
        <CategoriesManager
          categories={cats.map((c) => ({ ...c, usage: usage.get(c.id) ?? 0 }))}
          rules={rules}
        />
      </div>
    </>
  );
}
