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

export interface AddTxAccount {
  id: string;
  name: string;
  currency: string;
}

export interface AddTxCategory {
  id: string;
  name: string;
  color: string | null;
}

const UNCATEGORIZED = "__none__";

function toLocalDatetimeInput(d: Date): string {
  const off = d.getTimezoneOffset();
  return new Date(d.getTime() - off * 60_000).toISOString().slice(0, 16);
}

export function AddTransactionDialog({
  open,
  account,
  accountChoices,
  categories,
  onOpenChange,
  onSaved,
}: {
  open: boolean;
  account: AddTxAccount | null;
  accountChoices?: AddTxAccount[];
  categories: AddTxCategory[];
  onOpenChange: (open: boolean) => void;
  onSaved: () => void;
}) {
  const showPicker = !account && !!accountChoices && accountChoices.length > 0;
  const [pickedAccountId, setPickedAccountId] = useState<string>("");
  const [bookedAt, setBookedAt] = useState(toLocalDatetimeInput(new Date()));
  const [amount, setAmount] = useState("");
  const [currency, setCurrency] = useState("EUR");
  const [description, setDescription] = useState("");
  const [counterparty, setCounterparty] = useState("");
  const [categoryId, setCategoryId] = useState<string>(UNCATEGORIZED);
  const [submitting, setSubmitting] = useState(false);

  const effective = useMemo<AddTxAccount | null>(() => {
    if (account) return account;
    if (!accountChoices) return null;
    return accountChoices.find((a) => a.id === pickedAccountId) ?? null;
  }, [account, accountChoices, pickedAccountId]);

  useEffect(() => {
    if (!open) return;
    setBookedAt(toLocalDatetimeInput(new Date()));
    setAmount("");
    setDescription("");
    setCounterparty("");
    setCategoryId(UNCATEGORIZED);
    setPickedAccountId(
      account?.id ?? accountChoices?.[0]?.id ?? "",
    );
    // accountChoices is intentionally excluded — only reset on open/account
    // transitions, not on parent re-renders that produce a new array reference.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, account?.id]);

  useEffect(() => {
    if (effective) setCurrency(effective.currency);
  }, [effective]);

  async function submit() {
    if (!effective) {
      toast.error("Pick an account");
      return;
    }
    const n = Number(amount);
    if (!Number.isFinite(n) || n === 0) {
      toast.error("Amount must be a non-zero number");
      return;
    }
    setSubmitting(true);
    try {
      const res = await fetch(`/api/accounts/${effective.id}/transactions`, {
        method: "POST",
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
        const msg = typeof json?.error === "string" ? json.error : "Failed to add transaction";
        toast.error(msg);
        return;
      }
      if (json?.deduped) {
        toast.success("Already added (deduped)");
      } else if (json?.warnings?.length) {
        toast.success(`Added — ${json.warnings[0]}`);
      } else {
        toast.success("Transaction added");
      }
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
          <DialogTitle>
            Add transaction
            {effective ? ` — ${effective.name}` : ""}
          </DialogTitle>
          <DialogDescription>
            Negative amounts are debits, positive are credits. FX-to-EUR and
            category rules run automatically.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          {showPicker ? (
            <div className="space-y-1">
              <Label className="text-xs">Account</Label>
              <Select value={pickedAccountId} onValueChange={setPickedAccountId}>
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {accountChoices!.map((a) => (
                    <SelectItem key={a.id} value={a.id}>
                      {a.name}
                      <span className="ml-2 text-xs text-muted-foreground">
                        {a.currency}
                      </span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          ) : null}
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
                placeholder="-12.34"
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
              placeholder="e.g. Card fee"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-xs">Counterparty (optional)</Label>
            <Input
              value={counterparty}
              onChange={(e) => setCounterparty(e.target.value)}
              placeholder="e.g. Mercadona"
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)} disabled={submitting}>
            Cancel
          </Button>
          <Button
            onClick={submit}
            disabled={submitting || !effective || !amount || !bookedAt}
          >
            {submitting ? "Adding…" : "Add transaction"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
