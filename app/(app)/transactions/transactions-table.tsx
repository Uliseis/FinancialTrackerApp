"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import {
  ArrowDownLeft,
  ArrowUpRight,
  ArrowLeftRight,
  Search,
  Tag,
  Wand2,
} from "lucide-react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { formatCurrency, formatDate } from "@/lib/utils";

export interface TransactionsTableRow {
  id: string;
  bookedAt: Date;
  amount: string;
  currency: string;
  amountEur: string | null;
  direction: "credit" | "debit";
  description: string | null;
  counterparty: string | null;
  categoryId: string | null;
  categorySource: "bank" | "rule" | "manual" | null;
  isTransfer: boolean;
  accountId: string;
  accountName: string | null;
  institution: string | null;
}

export interface CategoryOption {
  id: string;
  name: string;
  color: string | null;
  kind: "expense" | "income";
}

const UNCATEGORIZED = "__none__";

export function TransactionsTable({
  rows,
  categories,
}: {
  rows: TransactionsTableRow[];
  categories: CategoryOption[];
}) {
  const router = useRouter();
  const [, startTransition] = useTransition();
  const [query, setQuery] = useState("");
  const [hideTransfers, setHideTransfers] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);

  const catById = useMemo(
    () => new Map(categories.map((c) => [c.id, c])),
    [categories],
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return rows.filter((r) => {
      if (hideTransfers && r.isTransfer) return false;
      if (!q) return true;
      const haystack = [r.description, r.counterparty, r.accountName, r.institution]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return haystack.includes(q);
    });
  }, [rows, query, hideTransfers]);

  async function setCategory(id: string, value: string) {
    setBusyId(id);
    try {
      const res = await fetch(`/api/transactions/${id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          categoryId: value === UNCATEGORIZED ? null : value,
        }),
      });
      if (!res.ok) throw new Error("Failed");
      startTransition(() => router.refresh());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Update failed");
    } finally {
      setBusyId(null);
    }
  }

  async function toggleTransfer(row: TransactionsTableRow) {
    setBusyId(row.id);
    try {
      const res = await fetch(`/api/transactions/${row.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ isTransfer: !row.isTransfer }),
      });
      if (!res.ok) throw new Error("Failed");
      toast.success(row.isTransfer ? "Unmarked as transfer" : "Marked as transfer");
      startTransition(() => router.refresh());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Update failed");
    } finally {
      setBusyId(null);
    }
  }

  async function runDetect() {
    const p = (async () => {
      const res = await fetch("/api/transactions/detect-transfers", { method: "POST" });
      if (!res.ok) throw new Error("Failed");
      return (await res.json()) as { scanned: number; matched: number };
    })();
    toast.promise(p, {
      loading: "Detecting transfers…",
      success: (r) => `Linked ${r.matched / 2} transfer pair${r.matched === 2 ? "" : "s"}`,
      error: "Detection failed",
    });
    try {
      await p;
      startTransition(() => router.refresh());
    } catch {
      // toast handled
    }
  }

  async function runRules() {
    const p = (async () => {
      const res = await fetch("/api/transactions/recategorize", { method: "POST" });
      if (!res.ok) throw new Error("Failed");
      return (await res.json()) as { updated: number; scanned: number };
    })();
    toast.promise(p, {
      loading: "Running category rules…",
      success: (r) => `Categorized ${r.updated} of ${r.scanned}`,
      error: "Failed",
    });
    try {
      await p;
      startTransition(() => router.refresh());
    } catch {
      // toast handled
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative w-full max-w-sm">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search description, counterparty, account…"
            className="pl-8"
          />
        </div>
        <label className="flex cursor-pointer select-none items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={hideTransfers}
            onChange={(e) => setHideTransfers(e.target.checked)}
            className="h-4 w-4 accent-current"
          />
          Hide transfers
        </label>
        <div className="ml-auto flex gap-2">
          <Button size="sm" variant="outline" onClick={runRules}>
            <Wand2 className="h-4 w-4" />
            Run rules
          </Button>
          <Button size="sm" variant="outline" onClick={runDetect}>
            <ArrowLeftRight className="h-4 w-4" />
            Detect transfers
          </Button>
        </div>
        <p className="text-xs text-muted-foreground">
          {filtered.length} of {rows.length}
        </p>
      </div>

      <div className="rounded-lg border border-border">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead className="w-[110px]">Date</TableHead>
              <TableHead>Account</TableHead>
              <TableHead>Description</TableHead>
              <TableHead className="w-[200px]">Category</TableHead>
              <TableHead className="text-right">Amount</TableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 ? (
              <TableRow className="hover:bg-transparent">
                <TableCell
                  colSpan={6}
                  className="py-10 text-center text-sm text-muted-foreground"
                >
                  Nothing matches.
                </TableCell>
              </TableRow>
            ) : (
              filtered.map((r) => {
                const positive = r.direction === "credit";
                const Icon = positive ? ArrowDownLeft : ArrowUpRight;
                const cat = r.categoryId ? catById.get(r.categoryId) : undefined;
                const eur = r.amountEur ? Number(r.amountEur) : null;
                return (
                  <TableRow key={r.id} className={r.isTransfer ? "opacity-70" : ""}>
                    <TableCell className="tabular text-sm text-muted-foreground">
                      {formatDate(r.bookedAt)}
                    </TableCell>
                    <TableCell>
                      <p className="text-sm font-medium">{r.accountName ?? "—"}</p>
                      <p className="text-xs text-muted-foreground">{r.institution}</p>
                    </TableCell>
                    <TableCell className="max-w-[280px]">
                      <p className="truncate text-sm">{r.description ?? ""}</p>
                      {r.counterparty ? (
                        <p className="truncate text-xs text-muted-foreground">
                          {r.counterparty}
                        </p>
                      ) : null}
                      {r.isTransfer ? (
                        <Badge variant="secondary" className="mt-1 text-[10px]">
                          <ArrowLeftRight className="mr-1 h-3 w-3" />
                          transfer
                        </Badge>
                      ) : null}
                    </TableCell>
                    <TableCell>
                      <Select
                        value={r.categoryId ?? UNCATEGORIZED}
                        onValueChange={(v) => setCategory(r.id, v)}
                        disabled={busyId === r.id}
                      >
                        <SelectTrigger className="w-full">
                          <SelectValue>
                            {cat ? (
                              <span className="flex items-center gap-2">
                                <span
                                  className="inline-block h-2.5 w-2.5 shrink-0 rounded-full"
                                  style={{ background: cat.color ?? "#64748b" }}
                                />
                                <span className="truncate">{cat.name}</span>
                                {r.categorySource ? (
                                  <Badge
                                    variant="outline"
                                    className="ml-1 text-[10px] uppercase"
                                  >
                                    {r.categorySource[0]}
                                  </Badge>
                                ) : null}
                              </span>
                            ) : (
                              <span className="text-muted-foreground">Uncategorized</span>
                            )}
                          </SelectValue>
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value={UNCATEGORIZED}>Uncategorized</SelectItem>
                          {categories.map((c) => (
                            <SelectItem key={c.id} value={c.id}>
                              <span className="flex items-center gap-2">
                                <span
                                  className="inline-block h-2.5 w-2.5 shrink-0 rounded-full"
                                  style={{ background: c.color ?? "#64748b" }}
                                />
                                {c.name}
                              </span>
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </TableCell>
                    <TableCell className="text-right">
                      <span
                        className={`tabular inline-flex items-center gap-1 text-sm font-medium ${
                          r.isTransfer
                            ? "text-muted-foreground"
                            : positive
                              ? "text-[var(--color-success)]"
                              : "text-foreground"
                        }`}
                      >
                        <Icon className="h-3 w-3 opacity-70" />
                        {positive ? "+" : ""}
                        {formatCurrency(parseFloat(r.amount), r.currency)}
                      </span>
                      {eur != null && r.currency !== "EUR" ? (
                        <p className="text-[11px] text-muted-foreground">
                          {formatCurrency(eur, "EUR")}
                        </p>
                      ) : null}
                    </TableCell>
                    <TableCell className="text-right">
                      <Button
                        variant="ghost"
                        size="icon"
                        aria-label={r.isTransfer ? "Unmark transfer" : "Mark as transfer"}
                        title={r.isTransfer ? "Unmark transfer" : "Mark as transfer"}
                        onClick={() => toggleTransfer(r)}
                        disabled={busyId === r.id}
                      >
                        <ArrowLeftRight className="h-4 w-4" />
                      </Button>
                    </TableCell>
                  </TableRow>
                );
              })
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}

export function TransactionsEmpty() {
  return (
    <div className="rounded-lg border border-dashed border-border p-10 text-center">
      <p className="text-sm font-medium">No transactions yet</p>
      <p className="mt-1 text-sm text-muted-foreground">
        Connect a bank to start syncing.
      </p>
      <Badge variant="outline" className="mt-4">
        <Tag className="mr-1 h-3 w-3" />
        Empty
      </Badge>
    </div>
  );
}
