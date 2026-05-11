"use client";

import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import {
  ArrowDownLeft,
  ArrowUpRight,
  ArrowLeftRight,
  ChevronLeft,
  ChevronRight,
  Link2,
  Link2Off,
  MoreHorizontal,
  Search,
  Tag,
  TrendingUp,
  Wand2,
  Wand,
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
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { formatCurrency, formatDate } from "@/lib/utils";
import type { CategoryKind } from "@/lib/income";
import {
  RULE_FIELDS,
  RULE_MATCH_TYPES,
  type RuleField,
  type RuleMatch,
} from "@/lib/rules";
import type { GroupSummary } from "@/lib/shared-expenses";

export type SharedExpenseSummary = GroupSummary;

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
  sharedExpenseGroupId: string | null;
  accountId: string;
  accountName: string | null;
  institution: string | null;
}

export interface CategoryOption {
  id: string;
  name: string;
  color: string | null;
  kind: CategoryKind;
}

const UNCATEGORIZED = "__none__";

export function TransactionsTable({
  rows,
  categories,
  sharedGroups,
  page,
  totalPages,
  total,
  pageSize,
  query: initialQuery,
  showTransfers: initialShowTransfers,
}: {
  rows: TransactionsTableRow[];
  categories: CategoryOption[];
  sharedGroups: SharedExpenseSummary[];
  page: number;
  totalPages: number;
  total: number;
  pageSize: number;
  query: string;
  showTransfers: boolean;
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();
  const [query, setQuery] = useState(initialQuery);
  const [showTransfers, setShowTransfers] = useState(initialShowTransfers);
  const [showSharedAs, setShowSharedAs] = useState<"net" | "gross">("net");
  const [busyId, setBusyId] = useState<string | null>(null);
  const [linkTarget, setLinkTarget] = useState<TransactionsTableRow | null>(null);
  const [classifyTarget, setClassifyTarget] = useState<TransactionsTableRow | null>(null);

  useEffect(() => setQuery(initialQuery), [initialQuery]);
  useEffect(() => setShowTransfers(initialShowTransfers), [initialShowTransfers]);

  const catById = useMemo(
    () => new Map(categories.map((c) => [c.id, c])),
    [categories],
  );
  const sortedCategories = useMemo(() => {
    const order: Record<CategoryKind, number> = {
      income: 0,
      expense: 1,
      reimbursement: 2,
      refund: 3,
    };
    return [...categories].sort((a, b) => {
      const ao = order[a.kind] ?? 9;
      const bo = order[b.kind] ?? 9;
      if (ao !== bo) return ao - bo;
      return a.name.localeCompare(b.name);
    });
  }, [categories]);
  const groupById = useMemo(
    () => new Map(sharedGroups.map((g) => [g.id, g])),
    [sharedGroups],
  );

  const firstRender = useRef(true);
  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    const t = window.setTimeout(() => {
      const params = new URLSearchParams();
      if (query.trim()) params.set("q", query.trim());
      if (showTransfers) params.set("transfers", "show");
      const qs = params.toString();
      startTransition(() => router.replace(qs ? `/transactions?${qs}` : "/transactions"));
    }, 250);
    return () => window.clearTimeout(t);
  }, [query, showTransfers, router]);

  function goToPage(target: number) {
    const params = new URLSearchParams();
    if (query.trim()) params.set("q", query.trim());
    if (showTransfers) params.set("transfers", "show");
    if (target > 1) params.set("page", String(target));
    const qs = params.toString();
    startTransition(() => router.replace(qs ? `/transactions?${qs}` : "/transactions"));
  }

  const rangeStart = total === 0 ? 0 : (page - 1) * pageSize + 1;
  const rangeEnd = Math.min(total, page * pageSize);

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

  async function unlinkFromGroup(row: TransactionsTableRow) {
    if (!row.sharedExpenseGroupId) return;
    const group = groupById.get(row.sharedExpenseGroupId);
    if (!group) return;
    setBusyId(row.id);
    try {
      if (group.primaryTxId === row.id) {
        const res = await fetch(`/api/shared-expenses/${group.id}`, { method: "DELETE" });
        if (!res.ok) throw new Error("Failed");
        toast.success(`Shared expense "${group.label}" removed`);
      } else {
        const res = await fetch(
          `/api/shared-expenses/${group.id}/links/${row.id}`,
          { method: "DELETE" },
        );
        if (!res.ok) throw new Error("Failed");
        toast.success("Unlinked reimbursement");
      }
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
    } catch {}
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
    } catch {}
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <div className="relative w-full max-w-sm">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search description or counterparty…"
            className="pl-8"
          />
        </div>
        <label className="flex cursor-pointer select-none items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={!showTransfers}
            onChange={(e) => setShowTransfers(!e.target.checked)}
            className="h-4 w-4 accent-current"
          />
          Hide transfers
        </label>
        <label className="flex cursor-pointer select-none items-center gap-2 text-sm">
          Shared:
          <select
            className="rounded-md border border-border bg-background px-2 py-1 text-sm"
            value={showSharedAs}
            onChange={(e) => setShowSharedAs(e.target.value as "net" | "gross")}
          >
            <option value="net">net</option>
            <option value="gross">gross</option>
          </select>
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
          {total === 0
            ? "0 results"
            : `${rangeStart.toLocaleString()}–${rangeEnd.toLocaleString()} of ${total.toLocaleString()}`}
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
            {rows.length === 0 ? (
              <TableRow className="hover:bg-transparent">
                <TableCell
                  colSpan={6}
                  className="py-10 text-center text-sm text-muted-foreground"
                >
                  Nothing matches.
                </TableCell>
              </TableRow>
            ) : (
              rows.map((r) => {
                const positive = r.direction === "credit";
                const Icon = positive ? ArrowDownLeft : ArrowUpRight;
                const cat = r.categoryId ? catById.get(r.categoryId) : undefined;
                const eur = r.amountEur ? Number(r.amountEur) : null;
                const group = r.sharedExpenseGroupId
                  ? groupById.get(r.sharedExpenseGroupId)
                  : undefined;
                const isPrimary = group ? group.primaryTxId === r.id : false;
                const showNet =
                  group && isPrimary && showSharedAs === "net";
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
                      <p className="truncate text-sm" title={r.description ?? ""}>
                        {r.description ?? <span className="text-muted-foreground">—</span>}
                      </p>
                      <p
                        className="truncate text-xs"
                        title={r.counterparty ?? "no counterparty on this transaction"}
                      >
                        <span className="mr-1 text-muted-foreground">
                          {positive ? "from:" : "to:"}
                        </span>
                        {r.counterparty ? (
                          <span className="font-medium">{r.counterparty}</span>
                        ) : (
                          <span className="italic text-muted-foreground">
                            (none — bank didn&apos;t provide one)
                          </span>
                        )}
                      </p>
                      <div className="mt-1 flex flex-wrap gap-1">
                        {r.isTransfer ? (
                          <Badge variant="secondary" className="text-[10px]">
                            <ArrowLeftRight className="mr-1 h-3 w-3" />
                            transfer
                          </Badge>
                        ) : null}
                        {group ? (
                          <Badge variant="outline" className="text-[10px]">
                            <Link2 className="mr-1 h-3 w-3" />
                            {isPrimary ? "shared" : "reimburses"}: {group.label} · net{" "}
                            {formatCurrency(group.net, "EUR")}
                          </Badge>
                        ) : null}
                      </div>
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
                          {sortedCategories.map((c) => (
                            <SelectItem key={c.id} value={c.id}>
                              <span className="flex items-center gap-2">
                                {c.kind === "income" ? (
                                  <TrendingUp className="h-3 w-3 text-[var(--color-success)]" />
                                ) : (
                                  <span
                                    className="inline-block h-2.5 w-2.5 shrink-0 rounded-full"
                                    style={{ background: c.color ?? "#64748b" }}
                                  />
                                )}
                                {c.name}
                                {c.kind !== "expense" ? (
                                  <span className="ml-1 text-[10px] uppercase text-muted-foreground">
                                    {c.kind}
                                  </span>
                                ) : null}
                              </span>
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </TableCell>
                    <TableCell className="text-right">
                      {showNet ? (
                        <div className="flex flex-col items-end">
                          <span className="text-xs text-muted-foreground line-through tabular">
                            {formatCurrency(parseFloat(r.amount), r.currency)}
                          </span>
                          <span className="tabular inline-flex items-center gap-1 text-sm font-medium">
                            <Icon className="h-3 w-3 opacity-70" />
                            {formatCurrency(group!.net, "EUR")}
                          </span>
                          <span className="text-[10px] uppercase text-muted-foreground">
                            net
                          </span>
                        </div>
                      ) : (
                        <>
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
                        </>
                      )}
                    </TableCell>
                    <TableCell className="text-right">
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <Button
                            variant="ghost"
                            size="icon"
                            aria-label="Row actions"
                            disabled={busyId === r.id}
                          >
                            <MoreHorizontal className="h-4 w-4" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuLabel>Actions</DropdownMenuLabel>
                          <DropdownMenuItem onClick={() => setClassifyTarget(r)}>
                            <Wand className="h-4 w-4" />
                            Classify like this…
                          </DropdownMenuItem>
                          <DropdownMenuItem onClick={() => toggleTransfer(r)}>
                            <ArrowLeftRight className="h-4 w-4" />
                            {r.isTransfer ? "Unmark transfer" : "Mark as transfer"}
                          </DropdownMenuItem>
                          {r.direction === "debit" && !r.isTransfer && !group ? (
                            <DropdownMenuItem onClick={() => setLinkTarget(r)}>
                              <Link2 className="h-4 w-4" />
                              Link reimbursements…
                            </DropdownMenuItem>
                          ) : null}
                          {group ? (
                            <>
                              <DropdownMenuSeparator />
                              <DropdownMenuItem onClick={() => unlinkFromGroup(r)}>
                                <Link2Off className="h-4 w-4" />
                                {isPrimary
                                  ? "Delete shared expense"
                                  : "Unlink from shared expense"}
                              </DropdownMenuItem>
                            </>
                          ) : null}
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </TableCell>
                  </TableRow>
                );
              })
            )}
          </TableBody>
        </Table>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-xs text-muted-foreground">
          Page {page} of {totalPages}
          {isPending ? " · loading…" : ""}
        </p>
        <div className="flex items-center gap-1">
          <Button
            size="sm"
            variant="outline"
            onClick={() => goToPage(page - 1)}
            disabled={page <= 1 || isPending}
          >
            <ChevronLeft className="h-4 w-4" />
            Previous
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={() => goToPage(page + 1)}
            disabled={page >= totalPages || isPending}
          >
            Next
            <ChevronRight className="h-4 w-4" />
          </Button>
        </div>
      </div>

      <LinkReimbursementsDialog
        primary={linkTarget}
        onClose={() => setLinkTarget(null)}
        onLinked={() => {
          setLinkTarget(null);
          startTransition(() => router.refresh());
        }}
      />
      <ClassifyLikeThisDialog
        target={classifyTarget}
        categories={sortedCategories}
        onClose={() => setClassifyTarget(null)}
        onSaved={() => {
          setClassifyTarget(null);
          startTransition(() => router.refresh());
        }}
      />
    </div>
  );
}

interface Candidate {
  id: string;
  bookedAt: string;
  amountEur: string | null;
  counterparty: string | null;
  description: string | null;
  accountId: string;
}

function LinkReimbursementsDialog({
  primary,
  onClose,
  onLinked,
}: {
  primary: TransactionsTableRow | null;
  onClose: () => void;
  onLinked: () => void;
}) {
  const [label, setLabel] = useState("");
  const [query, setQuery] = useState("");
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!primary) {
      setLabel("");
      setQuery("");
      setCandidates([]);
      setSelected(new Set());
      return;
    }
    const month = formatDate(primary.bookedAt);
    setLabel(`${primary.description ?? "Shared expense"} · ${month}`);
  }, [primary]);

  useEffect(() => {
    if (!primary) return;
    let cancelled = false;
    setLoading(true);
    const ctrl = new AbortController();
    const timer = window.setTimeout(async () => {
      try {
        const url = `/api/shared-expenses?candidatesFor=${primary.id}&q=${encodeURIComponent(query)}`;
        const res = await fetch(url, { signal: ctrl.signal });
        if (!res.ok) throw new Error("Failed to load candidates");
        const data = (await res.json()) as { candidates: Candidate[] };
        if (!cancelled) setCandidates(data.candidates);
      } catch (err) {
        if (!cancelled && (err as Error).name !== "AbortError") {
          toast.error((err as Error).message);
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    }, 200);
    return () => {
      cancelled = true;
      ctrl.abort();
      window.clearTimeout(timer);
    };
  }, [primary, query]);

  const primaryAmount = primary?.amountEur ? Math.abs(Number(primary.amountEur)) : 0;
  const reimbursedSum = useMemo(() => {
    let total = 0;
    for (const c of candidates) {
      if (selected.has(c.id) && c.amountEur) total += Math.abs(Number(c.amountEur));
    }
    return total;
  }, [candidates, selected]);
  const net = primaryAmount - reimbursedSum;

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function submit() {
    if (!primary) return;
    if (selected.size === 0) {
      toast.error("Pick at least one reimbursement");
      return;
    }
    if (!label.trim()) {
      toast.error("Label required");
      return;
    }
    setSubmitting(true);
    try {
      const res = await fetch("/api/shared-expenses", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          label: label.trim(),
          primaryTxId: primary.id,
          reimbursementTxIds: Array.from(selected),
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data?.error ?? "Failed");
      toast.success(`Linked — your share: ${formatCurrency(data.net.net, "EUR")}`);
      onLinked();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={!!primary} onOpenChange={(o) => (!o ? onClose() : undefined)}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Link reimbursements</DialogTitle>
          <DialogDescription>
            Pick the incoming Bizum / transfer credits that partially reimburse this
            expense. The net will be attributed to {primary ? formatDate(primary.bookedAt) : ""}.
          </DialogDescription>
        </DialogHeader>

        {primary ? (
          <div className="space-y-3">
            <div className="rounded-md border border-border p-3">
              <div className="flex items-center justify-between text-sm">
                <span>
                  <strong>{primary.description ?? "Expense"}</strong>
                  {primary.counterparty ? (
                    <span className="ml-2 text-muted-foreground">
                      {primary.counterparty}
                    </span>
                  ) : null}
                </span>
                <span className="tabular font-medium">
                  {formatCurrency(parseFloat(primary.amount), primary.currency)}
                </span>
              </div>
            </div>

            <Input
              placeholder="Label (e.g. Rent Mar 2026)"
              value={label}
              onChange={(e) => setLabel(e.target.value)}
            />

            <div className="relative">
              <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                placeholder="Filter by counterparty or description…"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                className="pl-8"
              />
            </div>

            <div className="max-h-80 overflow-auto rounded-md border border-border">
              {loading ? (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  Loading candidates…
                </p>
              ) : candidates.length === 0 ? (
                <p className="py-6 text-center text-sm text-muted-foreground">
                  No matching credits within ±60 days.
                </p>
              ) : (
                <ul>
                  {candidates.map((c) => {
                    const eur = c.amountEur ? Math.abs(Number(c.amountEur)) : 0;
                    return (
                      <li
                        key={c.id}
                        className="flex items-center gap-3 border-b border-border px-3 py-2 last:border-b-0"
                      >
                        <input
                          type="checkbox"
                          className="h-4 w-4 accent-current"
                          checked={selected.has(c.id)}
                          onChange={() => toggle(c.id)}
                        />
                        <div className="flex-1 text-sm">
                          <p className="truncate">
                            {c.description ?? c.counterparty ?? "—"}
                          </p>
                          <p className="text-xs text-muted-foreground">
                            {formatDate(new Date(c.bookedAt))}
                            {c.counterparty ? ` · ${c.counterparty}` : ""}
                          </p>
                        </div>
                        <span className="tabular text-sm font-medium">
                          {formatCurrency(eur, "EUR")}
                        </span>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>

            <div className="rounded-md bg-[var(--color-muted)] p-3 text-sm">
              Your share:{" "}
              <strong className="tabular">
                {formatCurrency(primaryAmount, "EUR")} −{" "}
                {formatCurrency(reimbursedSum, "EUR")} ={" "}
                {formatCurrency(Math.max(net, 0), "EUR")}
              </strong>
              {net < 0 ? (
                <span className="ml-2 text-[var(--color-destructive)]">
                  Over-reimbursed — adjust selection.
                </span>
              ) : null}
            </div>
          </div>
        ) : null}

        <DialogFooter>
          <Button variant="ghost" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting || net < 0}>
            {submitting ? "Linking…" : "Link reimbursements"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

interface PreviewSample {
  id: string;
  bookedAt: string;
  description: string | null;
  counterparty: string | null;
  amount: string;
  currency: string;
  direction: "credit" | "debit";
}

function ClassifyLikeThisDialog({
  target,
  categories,
  onClose,
  onSaved,
}: {
  target: TransactionsTableRow | null;
  categories: CategoryOption[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [field, setField] = useState<RuleField>("counterparty");
  const [matchType, setMatchType] = useState<RuleMatch>("contains");
  const [pattern, setPattern] = useState("");
  const [categoryId, setCategoryId] = useState<string>("");
  const [preview, setPreview] = useState<{ count: number; samples: PreviewSample[] } | null>(
    null,
  );
  const [previewing, setPreviewing] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!target) {
      setPattern("");
      setPreview(null);
      return;
    }
    const hasCp = !!target.counterparty;
    const defaultField: RuleField = hasCp ? "counterparty" : "description";
    setField(defaultField);
    setMatchType("contains");
    const seed = (hasCp ? target.counterparty : target.description) ?? "";
    setPattern(seed.trim());
    setCategoryId(target.categoryId ?? categories[0]?.id ?? "");
  }, [target, categories]);

  useEffect(() => {
    if (!target) return;
    if (!pattern.trim()) {
      setPreview({ count: 0, samples: [] });
      return;
    }
    let cancelled = false;
    const ctrl = new AbortController();
    setPreviewing(true);
    const timer = window.setTimeout(async () => {
      try {
        const res = await fetch("/api/category-rules/preview", {
          method: "POST",
          signal: ctrl.signal,
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ pattern: pattern.trim(), field, matchType }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data?.error ?? "preview failed");
        if (!cancelled) setPreview(data);
      } catch (err) {
        if (!cancelled && (err as Error).name !== "AbortError") {
          setPreview(null);
        }
      } finally {
        if (!cancelled) setPreviewing(false);
      }
    }, 250);
    return () => {
      cancelled = true;
      ctrl.abort();
      window.clearTimeout(timer);
    };
  }, [target, pattern, field, matchType]);

  async function submit() {
    if (!target) return;
    if (!pattern.trim()) {
      toast.error("Pattern can't be empty");
      return;
    }
    if (!categoryId) {
      toast.error("Pick a category");
      return;
    }
    setSubmitting(true);
    try {
      const ruleRes = await fetch("/api/category-rules", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          pattern: pattern.trim(),
          field,
          matchType,
          categoryId,
          priority: 0,
        }),
      });
      if (!ruleRes.ok) {
        const data = await ruleRes.json().catch(() => ({}));
        throw new Error(data?.error?.formErrors?.join(", ") ?? "Rule creation failed");
      }
      const applyRes = await fetch("/api/transactions/recategorize", { method: "POST" });
      const applyData = (await applyRes.json()) as { updated: number; scanned: number };
      if (!applyRes.ok) throw new Error("Applying rule failed");
      toast.success(
        `Rule saved — categorized ${applyData.updated} of ${applyData.scanned} transactions`,
      );
      onSaved();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={!!target} onOpenChange={(o) => (!o ? onClose() : undefined)}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Classify all like this</DialogTitle>
          <DialogDescription>
            Saves a rule and re-runs all rules across your transactions. Use the live
            preview to confirm it&apos;ll match the rows you expect.
          </DialogDescription>
        </DialogHeader>

        {target ? (
          <div className="space-y-3">
            <div className="rounded-md border border-border p-3 text-sm">
              <div className="flex items-center justify-between">
                <span className="truncate">
                  <strong>{target.description ?? "—"}</strong>
                </span>
                <span className="tabular font-medium">
                  {target.direction === "credit" ? "+" : ""}
                  {formatCurrency(parseFloat(target.amount), target.currency)}
                </span>
              </div>
              <p className="text-xs text-muted-foreground">
                {target.direction === "credit" ? "from" : "to"}:{" "}
                {target.counterparty ?? "(no counterparty on this row)"}
              </p>
            </div>

            <div className="grid grid-cols-1 gap-2 sm:grid-cols-[140px_140px_1fr]">
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Field</label>
                <select
                  className="h-9 w-full rounded-md border border-border bg-background px-2 text-sm"
                  value={field}
                  onChange={(e) => setField(e.target.value as RuleField)}
                >
                  {RULE_FIELDS.map((f) => (
                    <option key={f} value={f} className="capitalize">
                      {f}
                    </option>
                  ))}
                </select>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Match</label>
                <select
                  className="h-9 w-full rounded-md border border-border bg-background px-2 text-sm"
                  value={matchType}
                  onChange={(e) => setMatchType(e.target.value as RuleMatch)}
                >
                  {RULE_MATCH_TYPES.map((m) => (
                    <option key={m} value={m} className="capitalize">
                      {m}
                    </option>
                  ))}
                </select>
              </div>
              <div className="space-y-1">
                <label className="text-xs text-muted-foreground">Pattern</label>
                <Input
                  value={pattern}
                  onChange={(e) => setPattern(e.target.value)}
                  placeholder="e.g. MERCADONA"
                />
              </div>
            </div>

            <div className="space-y-1">
              <label className="text-xs text-muted-foreground">Category</label>
              <select
                className="h-9 w-full rounded-md border border-border bg-background px-2 text-sm"
                value={categoryId}
                onChange={(e) => setCategoryId(e.target.value)}
              >
                <option value="">Pick a category…</option>
                {categories.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                    {c.kind !== "expense" ? `  (${c.kind})` : ""}
                  </option>
                ))}
              </select>
            </div>

            <div className="rounded-md border border-border bg-[var(--color-muted)] p-3 text-sm">
              {previewing ? (
                <p className="text-muted-foreground">Checking…</p>
              ) : preview ? (
                <>
                  <p className="font-medium">
                    Matches {preview.count} transaction{preview.count === 1 ? "" : "s"}
                    {preview.count === 0 && pattern
                      ? " — try a shorter or broader pattern"
                      : ""}
                  </p>
                  {preview.samples.length > 0 ? (
                    <ul className="mt-2 space-y-1 text-xs">
                      {preview.samples.map((s) => (
                        <li key={s.id} className="flex items-center gap-2">
                          <span className="shrink-0 text-muted-foreground tabular">
                            {formatDate(new Date(s.bookedAt))}
                          </span>
                          <span className="truncate">
                            {s.description ?? s.counterparty ?? "—"}
                          </span>
                          <span className="ml-auto tabular">
                            {formatCurrency(parseFloat(s.amount), s.currency)}
                          </span>
                        </li>
                      ))}
                    </ul>
                  ) : null}
                </>
              ) : (
                <p className="text-muted-foreground">Enter a pattern to preview.</p>
              )}
            </div>

            {!target.counterparty && field === "counterparty" ? (
              <p className="text-xs text-[var(--color-warning)]">
                This row has no counterparty — switching to <strong>Description</strong>{" "}
                will match more reliably.
              </p>
            ) : null}
          </div>
        ) : null}

        <DialogFooter>
          <Button variant="ghost" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button
            onClick={submit}
            disabled={submitting || !pattern.trim() || !categoryId}
          >
            {submitting ? "Saving…" : "Save rule & apply"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
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
