"use client";

import { useEffect, useMemo, useState } from "react";
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
import type { AddTxCategory } from "./add-transaction-dialog";

export interface AddInterestAccount {
  id: string;
  name: string;
  currency: string;
}

const NO_CATEGORY = "__none__";

function toLocalDatetimeInput(d: Date): string {
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60_000).toISOString().slice(0, 16);
}

export function AddInterestDialog({
  open,
  account,
  suggestedAmount,
  categories,
  onOpenChange,
  onSaved,
}: {
  open: boolean;
  account: AddInterestAccount | null;
  suggestedAmount: number | null;
  categories: AddTxCategory[];
  onOpenChange: (open: boolean) => void;
  onSaved: () => void;
}) {
  const incomeCats = useMemo(
    () => categories.filter((c) => c.kind === "income"),
    [categories],
  );
  const defaultCategoryId = useMemo(() => {
    const otherIncome = incomeCats.find((c) => c.name === "Other Income");
    return otherIncome?.id ?? incomeCats[0]?.id ?? NO_CATEGORY;
  }, [incomeCats]);

  const [bookedAt, setBookedAt] = useState(toLocalDatetimeInput(new Date()));
  const [amount, setAmount] = useState("");
  const [categoryId, setCategoryId] = useState<string>(NO_CATEGORY);
  const [note, setNote] = useState("Interest");
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!open) return;
    setBookedAt(toLocalDatetimeInput(new Date()));
    setAmount(
      suggestedAmount && suggestedAmount > 0 ? suggestedAmount.toFixed(2) : "",
    );
    setCategoryId(defaultCategoryId);
    setNote("Interest");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, account?.id]);

  if (!account) return null;

  async function submit() {
    if (!account) return;
    const n = Number(amount);
    if (!Number.isFinite(n) || n <= 0) {
      toast.error("Amount must be a positive number");
      return;
    }
    setSubmitting(true);
    try {
      const res = await fetch(`/api/accounts/${account.id}/interest`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          bookedAt: new Date(bookedAt).toISOString(),
          amount: n,
          categoryId: categoryId === NO_CATEGORY ? null : categoryId,
          note: note.trim() || null,
        }),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        toast.error(
          typeof json?.error === "string" ? json.error : "Failed to post interest",
        );
        return;
      }
      toast.success(json?.deduped ? "Already added" : "Interest posted");
      onSaved();
      onOpenChange(false);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Post interest — {account.name}</DialogTitle>
          <DialogDescription>
            Records a credit on this account categorised as income. Use this to
            book accrued savings interest as a single tx — no need to enter
            daily 1-cent rows.
            {suggestedAmount != null && suggestedAmount > 0 ? (
              <>
                {" "}
                Suggested {suggestedAmount.toFixed(2)} {account.currency} — the
                drift between your bank balance and the anchored balance since
                the last reconciliation.
              </>
            ) : null}
          </DialogDescription>
        </DialogHeader>
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
            <Label className="text-xs">Amount ({account.currency})</Label>
            <Input
              type="number"
              step="0.01"
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
            />
          </div>
          <div className="space-y-1 sm:col-span-2">
            <Label className="text-xs">Category</Label>
            <Select value={categoryId} onValueChange={setCategoryId}>
              <SelectTrigger className="w-full">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value={NO_CATEGORY}>Uncategorized</SelectItem>
                {incomeCats.map((c) => (
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
          <div className="space-y-1 sm:col-span-2">
            <Label className="text-xs">Note</Label>
            <Input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="e.g. Monthly interest May 2026"
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={submitting || !amount || !bookedAt}>
            {submitting ? "Posting…" : "Post interest"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
