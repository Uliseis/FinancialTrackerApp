"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Plus, Trash2, Wand2 } from "lucide-react";
import type { Category, CategoryRule } from "@/db/schema";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

type CategoryWithUsage = Category & { usage: number };

export interface CategoriesManagerProps {
  categories: CategoryWithUsage[];
  rules: CategoryRule[];
}

export function CategoriesManager({ categories, rules }: CategoriesManagerProps) {
  const router = useRouter();
  const [, startTransition] = useTransition();

  const [newName, setNewName] = useState("");
  const [newKind, setNewKind] = useState<"expense" | "income">("expense");
  const [newColor, setNewColor] = useState("#64748b");
  const [creating, setCreating] = useState(false);

  const [rulePattern, setRulePattern] = useState("");
  const [ruleField, setRuleField] = useState<"description" | "counterparty">("description");
  const [ruleMatch, setRuleMatch] = useState<
    "contains" | "equals" | "startsWith" | "endsWith" | "regex"
  >("contains");
  const [ruleCategoryId, setRuleCategoryId] = useState<string>(categories[0]?.id ?? "");
  const [rulePriority, setRulePriority] = useState(0);
  const [creatingRule, setCreatingRule] = useState(false);

  async function createCategory() {
    if (!newName.trim()) return;
    setCreating(true);
    try {
      const res = await fetch("/api/categories", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: newName.trim(), kind: newKind, color: newColor }),
      });
      if (!res.ok) throw new Error((await res.json()).error?.formErrors?.join(", ") ?? "Failed");
      setNewName("");
      toast.success("Category added");
      startTransition(() => router.refresh());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Could not create category");
    } finally {
      setCreating(false);
    }
  }

  async function deleteCategory(id: string) {
    if (!confirm("Delete this category? Transactions using it will be uncategorized.")) return;
    const res = await fetch(`/api/categories/${id}`, { method: "DELETE" });
    if (!res.ok) {
      toast.error("Delete failed");
      return;
    }
    toast.success("Deleted");
    startTransition(() => router.refresh());
  }

  async function createRule() {
    if (!rulePattern.trim() || !ruleCategoryId) return;
    setCreatingRule(true);
    try {
      const res = await fetch("/api/category-rules", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          pattern: rulePattern.trim(),
          field: ruleField,
          matchType: ruleMatch,
          categoryId: ruleCategoryId,
          priority: rulePriority,
        }),
      });
      if (!res.ok) throw new Error("Failed");
      setRulePattern("");
      toast.success("Rule added");
      startTransition(() => router.refresh());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Could not create rule");
    } finally {
      setCreatingRule(false);
    }
  }

  async function deleteRule(id: string) {
    const res = await fetch(`/api/category-rules/${id}`, { method: "DELETE" });
    if (!res.ok) {
      toast.error("Delete failed");
      return;
    }
    toast.success("Deleted");
    startTransition(() => router.refresh());
  }

  async function recategorize() {
    const p = (async () => {
      const res = await fetch("/api/transactions/recategorize", { method: "POST" });
      if (!res.ok) throw new Error("Failed");
      return (await res.json()) as { updated: number; scanned: number };
    })();
    toast.promise(p, {
      loading: "Re-running rules…",
      success: (r) => `Updated ${r.updated} of ${r.scanned} transactions`,
      error: "Re-categorization failed",
    });
    try {
      await p;
      startTransition(() => router.refresh());
    } catch {
      // toast already surfaced
    }
  }

  const categoryById = new Map(categories.map((c) => [c.id, c]));

  return (
    <div className="grid gap-6 lg:grid-cols-2">
      <Card>
        <CardHeader>
          <CardTitle>Categories</CardTitle>
          <CardDescription>Used to bucket transactions and drive budgets.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-[1fr_140px_60px_auto] gap-2">
            <Input
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              placeholder="New category"
            />
            <Select
              value={newKind}
              onValueChange={(v) => setNewKind(v as "expense" | "income")}
            >
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="expense">Expense</SelectItem>
                <SelectItem value="income">Income</SelectItem>
              </SelectContent>
            </Select>
            <Input
              type="color"
              value={newColor}
              onChange={(e) => setNewColor(e.target.value)}
              className="h-9 w-12 cursor-pointer p-1"
            />
            <Button onClick={createCategory} disabled={creating || !newName.trim()} size="sm">
              <Plus className="h-4 w-4" />
              Add
            </Button>
          </div>

          <div className="rounded-lg border border-[var(--color-border)]">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead>Name</TableHead>
                  <TableHead>Kind</TableHead>
                  <TableHead className="text-right">Used</TableHead>
                  <TableHead className="w-12" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {categories.length === 0 ? (
                  <TableRow className="hover:bg-transparent">
                    <TableCell
                      colSpan={4}
                      className="py-6 text-center text-sm text-[var(--color-muted-foreground)]"
                    >
                      No categories yet.
                    </TableCell>
                  </TableRow>
                ) : (
                  categories.map((c) => (
                    <TableRow key={c.id}>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <span
                            className="inline-block h-3 w-3 rounded-full"
                            style={{ background: c.color ?? "#64748b" }}
                          />
                          <span className="text-sm font-medium">{c.name}</span>
                        </div>
                      </TableCell>
                      <TableCell className="text-sm capitalize">{c.kind}</TableCell>
                      <TableCell className="tabular text-right text-sm">{c.usage}</TableCell>
                      <TableCell className="text-right">
                        <Button
                          variant="ghost"
                          size="icon"
                          aria-label="Delete"
                          onClick={() => deleteCategory(c.id)}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-3">
          <div>
            <CardTitle>Rules</CardTitle>
            <CardDescription>
              When a transaction matches, it gets the rule&apos;s category. Manually edited rows are
              left alone.
            </CardDescription>
          </div>
          <Button size="sm" variant="outline" onClick={recategorize}>
            <Wand2 className="h-4 w-4" />
            Run rules
          </Button>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2 rounded-lg border border-[var(--color-border)] p-3">
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div className="space-y-1">
                <Label className="text-xs">Pattern</Label>
                <Input
                  value={rulePattern}
                  onChange={(e) => setRulePattern(e.target.value)}
                  placeholder="e.g. MERCADONA"
                />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Category</Label>
                <Select value={ruleCategoryId} onValueChange={setRuleCategoryId}>
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder="Pick a category" />
                  </SelectTrigger>
                  <SelectContent>
                    {categories.map((c) => (
                      <SelectItem key={c.id} value={c.id}>
                        {c.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Field</Label>
                <Select
                  value={ruleField}
                  onValueChange={(v) =>
                    setRuleField(v as "description" | "counterparty")
                  }
                >
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="description">Description</SelectItem>
                    <SelectItem value="counterparty">Counterparty</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Match</Label>
                <Select
                  value={ruleMatch}
                  onValueChange={(v) =>
                    setRuleMatch(
                      v as
                        | "contains"
                        | "equals"
                        | "startsWith"
                        | "endsWith"
                        | "regex",
                    )
                  }
                >
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="contains">Contains</SelectItem>
                    <SelectItem value="equals">Equals</SelectItem>
                    <SelectItem value="startsWith">Starts with</SelectItem>
                    <SelectItem value="endsWith">Ends with</SelectItem>
                    <SelectItem value="regex">Regex</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Priority</Label>
                <Input
                  type="number"
                  value={rulePriority}
                  onChange={(e) => setRulePriority(Number(e.target.value || 0))}
                />
              </div>
              <div className="flex items-end">
                <Button
                  onClick={createRule}
                  disabled={creatingRule || !rulePattern.trim() || !ruleCategoryId}
                  className="w-full"
                >
                  <Plus className="h-4 w-4" />
                  Add rule
                </Button>
              </div>
            </div>
          </div>

          <div className="rounded-lg border border-[var(--color-border)]">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead>Pattern</TableHead>
                  <TableHead>Field</TableHead>
                  <TableHead>Match</TableHead>
                  <TableHead>Category</TableHead>
                  <TableHead className="text-right">Priority</TableHead>
                  <TableHead className="w-12" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {rules.length === 0 ? (
                  <TableRow className="hover:bg-transparent">
                    <TableCell
                      colSpan={6}
                      className="py-6 text-center text-sm text-[var(--color-muted-foreground)]"
                    >
                      No rules yet.
                    </TableCell>
                  </TableRow>
                ) : (
                  rules.map((r) => {
                    const cat = categoryById.get(r.categoryId);
                    return (
                      <TableRow key={r.id}>
                        <TableCell className="text-sm font-medium">{r.pattern}</TableCell>
                        <TableCell className="text-xs capitalize">{r.field}</TableCell>
                        <TableCell className="text-xs capitalize">{r.matchType}</TableCell>
                        <TableCell>
                          <Badge variant="outline" className="text-xs">
                            {cat?.name ?? "—"}
                          </Badge>
                        </TableCell>
                        <TableCell className="tabular text-right text-sm">{r.priority}</TableCell>
                        <TableCell className="text-right">
                          <Button
                            variant="ghost"
                            size="icon"
                            aria-label="Delete rule"
                            onClick={() => deleteRule(r.id)}
                          >
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </TableCell>
                      </TableRow>
                    );
                  })
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
