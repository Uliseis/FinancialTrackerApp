"use client";

import { Fragment, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeftRight, ChevronDown, ChevronRight, Pencil, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { cn, formatCurrency, formatDate } from "@/lib/utils";
import { MoveDialog } from "./move-dialog";
import {
  ValuationDialog,
  type ExistingValuation,
} from "./valuation-dialog";

export interface AccountRow {
  accountId: string;
  accountName: string;
  institution: string;
  baselineAsOf: string | null;
  baselineEur: number | null;
  latestAsOf: string | null;
  latestEur: number | null;
  latestCashEur: number | null;
  latestPositionsEur: number | null;
  netContributionsSinceBaselineEur: number;
  costBasisEur: number | null;
  pnlEur: number | null;
  pnlPct: number | null;
  history: Array<{
    id: string;
    asOf: string;
    marketValueEur: string;
    cashValueEur: string | null;
    notes: string | null;
  }>;
}

export function InvestmentsManager({ rows }: { rows: AccountRow[] }) {
  const router = useRouter();
  const [pendingDelete, startDelete] = useTransition();
  const [open, setOpen] = useState(false);
  const [moveOpen, setMoveOpen] = useState(false);
  const [defaultAccountId, setDefaultAccountId] = useState<string | null>(null);
  const [editing, setEditing] = useState<ExistingValuation | null>(null);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  const accountsForDialog = rows.map((r) => ({ id: r.accountId, name: r.accountName }));

  function openCreate(accountId?: string) {
    setEditing(null);
    setDefaultAccountId(accountId ?? null);
    setOpen(true);
  }

  function openEdit(accountId: string, v: AccountRow["history"][number]) {
    setEditing({
      id: v.id,
      accountId,
      asOf: v.asOf,
      marketValueEur: v.marketValueEur,
      cashValueEur: v.cashValueEur,
      notes: v.notes,
    });
    setDefaultAccountId(accountId);
    setOpen(true);
  }

  function toggleExpand(accountId: string) {
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(accountId)) next.delete(accountId);
      else next.add(accountId);
      return next;
    });
  }

  function deleteValuation(id: string) {
    if (!confirm("Delete this valuation?")) return;
    startDelete(async () => {
      const res = await fetch(`/api/investments/valuations/${id}`, { method: "DELETE" });
      if (!res.ok) {
        toast.error("Delete failed");
        return;
      }
      toast.success("Deleted");
      router.refresh();
    });
  }

  return (
    <>
      <Card>
        <CardHeader className="flex flex-row items-center justify-between">
          <CardTitle>Accounts</CardTitle>
          <div className="flex gap-2">
            {rows.length >= 2 ? (
              <Button size="sm" variant="outline" onClick={() => setMoveOpen(true)}>
                <ArrowLeftRight className="h-4 w-4" />
                Move
              </Button>
            ) : null}
            <Button size="sm" onClick={() => openCreate()}>
              <Plus className="h-4 w-4" />
              Record valuation
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead className="w-8" />
                <TableHead>Account</TableHead>
                <TableHead>Baseline</TableHead>
                <TableHead className="text-right">Invested</TableHead>
                <TableHead className="text-right">Market value</TableHead>
                <TableHead className="text-right">P&amp;L</TableHead>
                <TableHead>Last update</TableHead>
                <TableHead />
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => {
                const isOpen = expanded.has(r.accountId);
                const pnlPositive = (r.pnlEur ?? 0) >= 0;
                return (
                  <Fragment key={r.accountId}>
                    <TableRow>
                      <TableCell>
                        <button
                          onClick={() => toggleExpand(r.accountId)}
                          className="text-muted-foreground"
                          aria-label={isOpen ? "Collapse" : "Expand"}
                        >
                          {isOpen ? (
                            <ChevronDown className="h-4 w-4" />
                          ) : (
                            <ChevronRight className="h-4 w-4" />
                          )}
                        </button>
                      </TableCell>
                      <TableCell>
                        <div className="font-medium">{r.accountName}</div>
                        <div className="text-xs text-muted-foreground">{r.institution}</div>
                      </TableCell>
                      <TableCell>
                        {r.baselineAsOf ? (
                          <div className="text-xs">
                            <div>{formatDate(r.baselineAsOf)}</div>
                            <div className="text-muted-foreground">
                              {formatCurrency(r.baselineEur ?? 0, "EUR")}
                            </div>
                          </div>
                        ) : (
                          <Badge variant="outline" className="text-[10px] uppercase">
                            No baseline
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-right tabular">
                        {r.costBasisEur != null ? (
                          <div>
                            <div>{formatCurrency(r.costBasisEur, "EUR")}</div>
                            <div className="text-xs text-muted-foreground">
                              {r.netContributionsSinceBaselineEur >= 0 ? "+" : ""}
                              {formatCurrency(r.netContributionsSinceBaselineEur, "EUR")} since
                            </div>
                          </div>
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </TableCell>
                      <TableCell className="text-right tabular font-medium">
                        {r.latestEur != null ? (
                          <div>
                            <div>{formatCurrency(r.latestEur, "EUR")}</div>
                            {r.latestCashEur != null && r.latestPositionsEur != null ? (
                              <div className="text-xs font-normal text-muted-foreground">
                                {formatCurrency(r.latestPositionsEur, "EUR")} pos ·{" "}
                                {formatCurrency(r.latestCashEur, "EUR")} cash
                              </div>
                            ) : null}
                          </div>
                        ) : (
                          <span className="text-muted-foreground">—</span>
                        )}
                      </TableCell>
                      <TableCell
                        className={cn(
                          "text-right tabular",
                          r.pnlEur == null
                            ? "text-muted-foreground"
                            : pnlPositive
                            ? "text-[var(--color-success)]"
                            : "text-[var(--color-destructive)]",
                        )}
                      >
                        {r.pnlEur != null ? (
                          <div>
                            <div>
                              {pnlPositive ? "+" : ""}
                              {formatCurrency(r.pnlEur, "EUR")}
                            </div>
                            {r.pnlPct != null ? (
                              <div className="text-xs">
                                {pnlPositive ? "+" : ""}
                                {(r.pnlPct * 100).toFixed(1)}%
                              </div>
                            ) : null}
                          </div>
                        ) : (
                          "—"
                        )}
                      </TableCell>
                      <TableCell className="text-xs text-muted-foreground">
                        {r.latestAsOf ? formatDate(r.latestAsOf) : "—"}
                      </TableCell>
                      <TableCell className="text-right">
                        <Button
                          size="sm"
                          variant={r.baselineAsOf ? "outline" : "default"}
                          onClick={() => openCreate(r.accountId)}
                        >
                          {r.baselineAsOf ? "Add" : "Set baseline"}
                        </Button>
                      </TableCell>
                    </TableRow>
                    {isOpen ? (
                      <TableRow className="bg-[var(--color-muted)]/30 hover:bg-[var(--color-muted)]/30">
                        <TableCell />
                        <TableCell colSpan={7}>
                          {r.history.length === 0 ? (
                            <p className="text-sm text-muted-foreground">
                              No valuations recorded yet.
                            </p>
                          ) : (
                            <Table>
                              <TableHeader>
                                <TableRow className="hover:bg-transparent">
                                  <TableHead>Date</TableHead>
                                  <TableHead className="text-right">Value</TableHead>
                                  <TableHead>Notes</TableHead>
                                  <TableHead />
                                </TableRow>
                              </TableHeader>
                              <TableBody>
                                {r.history.map((h) => (
                                  <TableRow key={h.id} className="hover:bg-transparent">
                                    <TableCell className="text-xs">
                                      {formatDate(h.asOf)}
                                    </TableCell>
                                    <TableCell className="text-right text-xs tabular">
                                      <div>{formatCurrency(Number(h.marketValueEur), "EUR")}</div>
                                      {h.cashValueEur != null ? (
                                        <div className="text-[10px] text-muted-foreground">
                                          {formatCurrency(
                                            Math.max(
                                              0,
                                              Number(h.marketValueEur) - Number(h.cashValueEur),
                                            ),
                                            "EUR",
                                          )}{" "}
                                          pos · {formatCurrency(Number(h.cashValueEur), "EUR")} cash
                                        </div>
                                      ) : null}
                                    </TableCell>
                                    <TableCell className="text-xs text-muted-foreground">
                                      {h.notes ?? ""}
                                    </TableCell>
                                    <TableCell className="text-right">
                                      <div className="inline-flex gap-1">
                                        <Button
                                          size="sm"
                                          variant="ghost"
                                          onClick={() => openEdit(r.accountId, h)}
                                        >
                                          <Pencil className="h-3.5 w-3.5" />
                                        </Button>
                                        <Button
                                          size="sm"
                                          variant="ghost"
                                          disabled={pendingDelete}
                                          onClick={() => deleteValuation(h.id)}
                                        >
                                          <Trash2 className="h-3.5 w-3.5" />
                                        </Button>
                                      </div>
                                    </TableCell>
                                  </TableRow>
                                ))}
                              </TableBody>
                            </Table>
                          )}
                        </TableCell>
                      </TableRow>
                    ) : null}
                  </Fragment>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <ValuationDialog
        open={open}
        onOpenChange={setOpen}
        accounts={accountsForDialog}
        defaultAccountId={defaultAccountId}
        existing={editing}
      />

      <MoveDialog
        open={moveOpen}
        onOpenChange={setMoveOpen}
        accounts={accountsForDialog}
      />
    </>
  );
}
