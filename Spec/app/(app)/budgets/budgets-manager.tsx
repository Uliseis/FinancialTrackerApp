"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Plus, Trash2 } from "lucide-react";
import type { Budget, Category } from "@/db/schema";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Progress } from "@/components/ui/progress";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { formatCurrency, formatDate } from "@/lib/utils";

export interface BudgetRow extends Budget {
  categoryName: string;
  categoryColor: string | null;
  spentEur: number;
  periodStart: Date | null;
  periodEnd: Date | null;
}

export interface BudgetsManagerProps {
  rows: BudgetRow[];
  categories: Category[];
}

type Period = "week" | "month" | "year";

function todayIso(): string {
  const d = new Date();
  return d.toISOString().slice(0, 10);
}

function firstOfMonthIso(): string {
  const d = new Date();
  d.setUTCDate(1);
  return d.toISOString().slice(0, 10);
}

export function BudgetsManager({ rows, categories }: BudgetsManagerProps) {
  const router = useRouter();
  const [, startTransition] = useTransition();

  const expenseCats = categories.filter((c) => c.kind !== "income");

  const [catId, setCatId] = useState<string>(expenseCats[0]?.id ?? "");
  const [amount, setAmount] = useState("");
  const [period, setPeriod] = useState<Period>("month");
  const [startsOn, setStartsOn] = useState<string>(firstOfMonthIso());
  const [creating, setCreating] = useState(false);

  async function createBudget() {
    if (!catId || !amount.trim()) return;
    setCreating(true);
    try {
      const res = await fetch("/api/budgets", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          categoryId: catId,
          amountEur: amount,
          period,
          startsOn,
        }),
      });
      if (!res.ok) throw new Error("Failed");
      setAmount("");
      toast.success("Budget created");
      startTransition(() => router.refresh());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setCreating(false);
    }
  }

  async function deleteBudget(id: string) {
    if (!confirm("Delete this budget?")) return;
    const res = await fetch(`/api/budgets/${id}`, { method: "DELETE" });
    if (!res.ok) {
      toast.error("Failed");
      return;
    }
    toast.success("Deleted");
    startTransition(() => router.refresh());
  }

  async function toggleActive(b: BudgetRow) {
    const res = await fetch(`/api/budgets/${b.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ active: !b.active }),
    });
    if (!res.ok) {
      toast.error("Failed");
      return;
    }
    startTransition(() => router.refresh());
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>New budget</CardTitle>
          <CardDescription>
            Choose a category, a target amount, and how often the window resets.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-5">
            <div className="space-y-1 sm:col-span-2">
              <Label className="text-xs">Category</Label>
              <Select value={catId} onValueChange={setCatId}>
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Pick a category" />
                </SelectTrigger>
                <SelectContent>
                  {expenseCats.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Amount (EUR)</Label>
              <Input
                type="number"
                step="0.01"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="400.00"
              />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Period</Label>
              <Select value={period} onValueChange={(v) => setPeriod(v as Period)}>
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="week">Weekly</SelectItem>
                  <SelectItem value="month">Monthly</SelectItem>
                  <SelectItem value="year">Yearly</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Starts on</Label>
              <Input
                type="date"
                value={startsOn}
                onChange={(e) => setStartsOn(e.target.value)}
                max={todayIso()}
              />
            </div>
            <div className="sm:col-span-5">
              <Button
                onClick={createBudget}
                disabled={creating || !catId || !amount.trim()}
              >
                <Plus className="h-4 w-4" />
                Add budget
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        {rows.length === 0 ? (
          <Card className="lg:col-span-2">
            <CardContent className="py-10 text-center text-sm text-muted-foreground">
              No budgets yet. Add one above to start tracking spend vs target.
            </CardContent>
          </Card>
        ) : (
          rows.map((b) => {
            const amt = Number(b.amountEur);
            const pct = amt > 0 ? Math.min(100, (b.spentEur / amt) * 100) : 0;
            const over = b.spentEur > amt;
            return (
              <Card key={b.id} className={!b.active ? "opacity-60" : ""}>
                <CardHeader className="flex flex-row items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span
                        className="inline-block h-3 w-3 rounded-full"
                        style={{ background: b.categoryColor ?? "#64748b" }}
                      />
                      <CardTitle className="truncate text-base">
                        {b.categoryName}
                      </CardTitle>
                      <Badge variant="outline" className="text-[10px] uppercase">
                        {b.period}
                      </Badge>
                      {!b.active ? (
                        <Badge variant="secondary" className="text-[10px]">
                          paused
                        </Badge>
                      ) : null}
                    </div>
                    <CardDescription className="mt-1">
                      {b.periodStart && b.periodEnd
                        ? `${formatDate(b.periodStart)} – ${formatDate(
                            new Date(b.periodEnd.getTime() - 1),
                          )}`
                        : "Period pending"}
                    </CardDescription>
                  </div>
                  <div className="flex items-center gap-1">
                    <Button
                      size="sm"
                      variant="ghost"
                      onClick={() => toggleActive(b)}
                    >
                      {b.active ? "Pause" : "Resume"}
                    </Button>
                    <Button
                      variant="ghost"
                      size="icon"
                      aria-label="Delete budget"
                      onClick={() => deleteBudget(b.id)}
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </CardHeader>
                <CardContent className="space-y-2">
                  <div className="flex items-baseline justify-between">
                    <p className="tabular text-2xl font-semibold">
                      {formatCurrency(b.spentEur, "EUR")}
                    </p>
                    <p className="tabular text-sm text-muted-foreground">
                      of {formatCurrency(amt, "EUR")}
                    </p>
                  </div>
                  <Progress
                    value={pct}
                    className={over ? "[&>[data-slot=progress-indicator]]:bg-destructive" : ""}
                  />
                  <p
                    className={`text-xs ${
                      over ? "text-destructive" : "text-muted-foreground"
                    }`}
                  >
                    {over
                      ? `Over by ${formatCurrency(b.spentEur - amt, "EUR")}`
                      : `${formatCurrency(amt - b.spentEur, "EUR")} remaining`}
                  </p>
                </CardContent>
              </Card>
            );
          })
        )}
      </div>
    </div>
  );
}
