"use client";

import { useEffect, useState } from "react";
import { toast } from "sonner";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import type { TransactionsTableRow, CategoryOption } from "./transactions-table";

const UNCATEGORIZED = "__none__";

function toLocalDatetimeInput(d: Date): string {
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60_000).toISOString().slice(0, 16);
}

export function EditTransactionDialog({
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
  const [bookedAt, setBookedAt] = useState("");
  const [amount, setAmount] = useState("");
  const [currency, setCurrency] = useState("EUR");
  const [description, setDescription] = useState("");
  const [counterparty, setCounterparty] = useState("");
  const [categoryId, setCategoryId] = useState<string>(UNCATEGORIZED);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!target) return;
    setBookedAt(toLocalDatetimeInput(new Date(target.bookedAt)));
    setAmount(target.amount);
    setCurrency(target.currency);
    setDescription(target.description ?? "");
    setCounterparty(target.counterparty ?? "");
    setCategoryId(target.categoryId ?? UNCATEGORIZED);
  }, [target?.id]);

  if (!target) return null;

  async function submit() {
    if (!target) return;
    const n = Number(amount);
    if (!Number.isFinite(n) || n === 0) {
      toast.error("Amount must be a non-zero number");
      return;
    }
    setSubmitting(true);
    try {
      const res = await fetch(`/api/transactions/${target.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          bookedAt: new Date(bookedAt).toISOString(),
          amount: n,
          currency: currency.trim().toUpperCase(),
          description: description.trim() || null,
          counterparty: counterparty.trim() || null,
          categoryId: categoryId === UNCATEGORIZED ? null : categoryId,
        }),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        const msg = typeof json?.error === "string" ? json.error : "Failed to save";
        toast.error(msg);
        return;
      }
      if (json?.warnings?.length) {
        toast.success(`Saved — ${json.warnings[0]}`);
      } else {
        toast.success("Saved");
      }
      onSaved();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={!!target} onOpenChange={(o) => (!o ? onClose() : undefined)}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Edit transaction</DialogTitle>
          <DialogDescription>
            {target.accountName ?? "—"} · {target.institution ?? ""}. Changing
            amount or currency triggers an FX re-conversion.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div className="space-y-1">
              <Label className="text-xs">Booked at</Label>
              <Input
                type="datetime-local"
                value={bookedAt}
                onChange={(e) => setBookedAt(e.target.value)}
              />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Amount</Label>
              <Input
                type="number"
                step="0.01"
                inputMode="decimal"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
              />
              <p className="text-[10px] text-muted-foreground">
                Negative = debit, positive = credit
              </p>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Currency</Label>
              <Input
                value={currency}
                onChange={(e) => setCurrency(e.target.value)}
                maxLength={3}
              />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Category</Label>
              <Select value={categoryId} onValueChange={setCategoryId}>
                <SelectTrigger className="w-full">
                  <SelectValue />
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
            </div>
          </div>
          <div className="space-y-1">
            <Label className="text-xs">Description</Label>
            <Input
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>
          <div className="space-y-1">
            <Label className="text-xs">Counterparty</Label>
            <Input
              value={counterparty}
              onChange={(e) => setCounterparty(e.target.value)}
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting || !amount || !bookedAt}>
            {submitting ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
