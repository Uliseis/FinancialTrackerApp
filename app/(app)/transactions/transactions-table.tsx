"use client";

import { useMemo, useState } from "react";
import { ArrowDownLeft, ArrowUpRight, Search } from "lucide-react";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { formatCurrency, formatDate } from "@/lib/utils";

export interface TransactionsTableRow {
  id: string;
  bookedAt: Date;
  amount: string;
  currency: string;
  direction: "credit" | "debit";
  description: string | null;
  counterparty: string | null;
  accountName: string | null;
  institution: string | null;
}

export function TransactionsTable({ rows }: { rows: TransactionsTableRow[] }) {
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((r) => {
      const haystack = [
        r.description,
        r.counterparty,
        r.accountName,
        r.institution,
      ]
        .filter(Boolean)
        .join(" ")
        .toLowerCase();
      return haystack.includes(q);
    });
  }, [rows, query]);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        <div className="relative w-full max-w-sm">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--color-muted-foreground)]" />
          <Input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search description, counterparty, account…"
            className="pl-8"
          />
        </div>
        <p className="text-xs text-[var(--color-muted-foreground)]">
          {filtered.length} of {rows.length}
        </p>
      </div>

      <div className="rounded-lg border border-[var(--color-border)]">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead className="w-[110px]">Date</TableHead>
              <TableHead>Account</TableHead>
              <TableHead>Description</TableHead>
              <TableHead>Counterparty</TableHead>
              <TableHead className="text-right">Amount</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length === 0 ? (
              <TableRow className="hover:bg-transparent">
                <TableCell
                  colSpan={5}
                  className="py-10 text-center text-sm text-[var(--color-muted-foreground)]"
                >
                  No transactions match that search.
                </TableCell>
              </TableRow>
            ) : (
              filtered.map((r) => {
                const positive = r.direction === "credit";
                const Icon = positive ? ArrowDownLeft : ArrowUpRight;
                return (
                  <TableRow key={r.id}>
                    <TableCell className="tabular text-sm text-[var(--color-muted-foreground)]">
                      {formatDate(r.bookedAt)}
                    </TableCell>
                    <TableCell>
                      <p className="text-sm font-medium">{r.accountName ?? "—"}</p>
                      <p className="text-xs text-[var(--color-muted-foreground)]">
                        {r.institution}
                      </p>
                    </TableCell>
                    <TableCell className="max-w-[320px] truncate text-sm">
                      {r.description ?? ""}
                    </TableCell>
                    <TableCell className="max-w-[200px] truncate text-sm">
                      {r.counterparty ?? ""}
                    </TableCell>
                    <TableCell className="text-right">
                      <span
                        className={`tabular inline-flex items-center gap-1 text-sm font-medium ${
                          positive
                            ? "text-[var(--color-success)]"
                            : "text-[var(--color-foreground)]"
                        }`}
                      >
                        <Icon className="h-3 w-3 opacity-70" />
                        {positive ? "+" : ""}
                        {formatCurrency(parseFloat(r.amount), r.currency)}
                      </span>
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
    <div className="rounded-lg border border-dashed border-[var(--color-border)] p-10 text-center">
      <p className="text-sm font-medium">No transactions yet</p>
      <p className="mt-1 text-sm text-[var(--color-muted-foreground)]">
        Connect a bank to start syncing.
      </p>
      <Badge variant="outline" className="mt-4">
        Empty
      </Badge>
    </div>
  );
}
