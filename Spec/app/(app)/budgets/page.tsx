import { asc } from "drizzle-orm";
import { db } from "@/lib/db";
import { budgets, categories } from "@/db/schema";
import { PageHeader } from "@/components/page-header";
import { activeBudgetsProgress } from "@/lib/budgets";
import { BudgetsManager } from "./budgets-manager";

export const dynamic = "force-dynamic";

export default async function BudgetsPage() {
  const [allBudgets, cats, progress] = await Promise.all([
    db.select().from(budgets),
    db.select().from(categories).orderBy(asc(categories.name)),
    activeBudgetsProgress(),
  ]);

  const progressById = new Map(progress.map((p) => [p.budget.id, p]));

  const rows = allBudgets.map((b) => {
    const cat = cats.find((c) => c.id === b.categoryId);
    const p = progressById.get(b.id);
    return {
      ...b,
      categoryName: cat?.name ?? "—",
      categoryColor: cat?.color ?? null,
      spentEur: p?.spentEur ?? 0,
      periodStart: p?.period.start ?? null,
      periodEnd: p?.period.end ?? null,
    };
  });

  return (
    <>
      <PageHeader
        title="Budgets"
        description="Set spend limits per category. Internal transfers don't count."
      />
      <div className="p-6">
        <BudgetsManager rows={rows} categories={cats} />
      </div>
    </>
  );
}
