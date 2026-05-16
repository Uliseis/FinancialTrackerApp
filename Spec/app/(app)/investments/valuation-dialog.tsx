"use client";

import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
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
import { NativeSelect } from "@/components/ui/select";

export interface ValuationDialogAccount {
  id: string;
  name: string;
}

export interface ExistingValuation {
  id: string;
  accountId: string;
  asOf: string; // YYYY-MM-DD
  marketValueEur: string;
  cashValueEur: string | null;
  notes: string | null;
}

export function ValuationDialog({
  open,
  onOpenChange,
  accounts,
  defaultAccountId,
  existing,
  defaultAsOf,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  accounts: ValuationDialogAccount[];
  defaultAccountId?: string | null;
  existing?: ExistingValuation | null;
  defaultAsOf?: string;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const todayLocal = (): string => {
    const now = new Date();
    const y = now.getFullYear();
    const m = String(now.getMonth() + 1).padStart(2, "0");
    const d = String(now.getDate()).padStart(2, "0");
    return `${y}-${m}-${d}`;
  };
  const [accountId, setAccountId] = useState<string>(defaultAccountId ?? accounts[0]?.id ?? "");
  const [asOf, setAsOf] = useState<string>(defaultAsOf ?? todayLocal());
  const [marketValueEur, setMarketValueEur] = useState<string>("");
  const [cashValueEur, setCashValueEur] = useState<string>("");
  const [notes, setNotes] = useState<string>("");

  useEffect(() => {
    if (!open) return;
    if (existing) {
      setAccountId(existing.accountId);
      setAsOf(existing.asOf);
      setMarketValueEur(Number(existing.marketValueEur).toFixed(2));
      setCashValueEur(
        existing.cashValueEur != null ? Number(existing.cashValueEur).toFixed(2) : "",
      );
      setNotes(existing.notes ?? "");
    } else {
      setAccountId(defaultAccountId ?? accounts[0]?.id ?? "");
      setAsOf(defaultAsOf ?? todayLocal());
      setMarketValueEur("");
      setCashValueEur("");
      setNotes("");
    }
  }, [open, existing, defaultAccountId, defaultAsOf, accounts]);

  function submit() {
    if (!accountId) {
      toast.error("Pick an account");
      return;
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(asOf)) {
      toast.error("Date must be YYYY-MM-DD");
      return;
    }
    if (!/^\d+(\.\d{1,2})?$/.test(marketValueEur)) {
      toast.error("Market value must be a non-negative number (max 2 decimals)");
      return;
    }
    const cashTrimmed = cashValueEur.trim();
    if (!/^\d+(\.\d{1,2})?$/.test(cashTrimmed)) {
      toast.error("Cash portion is required (use 0 if fully invested)");
      return;
    }
    if (Number(cashTrimmed) > Number(marketValueEur)) {
      toast.error("Cash portion cannot exceed total market value");
      return;
    }
    startTransition(async () => {
      const body = JSON.stringify({
        accountId,
        asOf,
        marketValueEur,
        cashValueEur: cashTrimmed,
        notes: notes.trim() ? notes.trim() : null,
      });
      const url = existing
        ? `/api/investments/valuations/${existing.id}`
        : "/api/investments/valuations";
      const method = existing ? "PATCH" : "POST";
      const res = await fetch(url, {
        method,
        headers: { "content-type": "application/json" },
        body,
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        toast.error(typeof data?.error === "string" ? data.error : "Save failed");
        return;
      }
      toast.success(existing ? "Valuation updated" : "Valuation saved");
      onOpenChange(false);
      router.refresh();
    });
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{existing ? "Edit valuation" : "Record valuation"}</DialogTitle>
          <DialogDescription>
            Enter the end-of-day EUR market value of the account on a given date.
            Contributions and withdrawals after the baseline date are counted toward
            cost basis automatically.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4">
          <div className="grid gap-2">
            <Label htmlFor="account">Account</Label>
            <NativeSelect
              id="account"
              value={accountId}
              onChange={(e) => setAccountId(e.target.value)}
              disabled={!!existing}
            >
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </NativeSelect>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="grid gap-2">
              <Label htmlFor="asOf">Date</Label>
              <Input
                id="asOf"
                type="date"
                value={asOf}
                onChange={(e) => setAsOf(e.target.value)}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="value">Total value (EUR)</Label>
              <Input
                id="value"
                type="number"
                step="0.01"
                inputMode="decimal"
                placeholder="19800.00"
                value={marketValueEur}
                onChange={(e) => setMarketValueEur(e.target.value)}
              />
            </div>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="cash">Of which, cash (EUR)</Label>
            <Input
              id="cash"
              type="number"
              step="0.01"
              inputMode="decimal"
              placeholder="0.00 if fully invested"
              value={cashValueEur}
              onChange={(e) => setCashValueEur(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              Un-invested EUR sitting in the broker. The rest is treated as deployed in
              positions.
            </p>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="notes">Notes (optional)</Label>
            <Input
              id="notes"
              placeholder="end-of-month statement"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={pending}>
            {pending ? "Saving…" : existing ? "Save" : "Record"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
