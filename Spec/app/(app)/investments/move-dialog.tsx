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

export interface MoveDialogAccount {
  id: string;
  name: string;
}

function todayLocal(): string {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function MoveDialog({
  open,
  onOpenChange,
  accounts,
  defaultFromId,
  defaultToId,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  accounts: MoveDialogAccount[];
  defaultFromId?: string | null;
  defaultToId?: string | null;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [fromId, setFromId] = useState<string>(defaultFromId ?? accounts[0]?.id ?? "");
  const [toId, setToId] = useState<string>(
    defaultToId ?? accounts.find((a) => a.id !== (defaultFromId ?? accounts[0]?.id))?.id ?? "",
  );
  const [amount, setAmount] = useState<string>("");
  const [bookedAt, setBookedAt] = useState<string>(todayLocal());
  const [description, setDescription] = useState<string>("");

  useEffect(() => {
    if (!open) return;
    const initialFrom = defaultFromId ?? accounts[0]?.id ?? "";
    setFromId(initialFrom);
    setToId(
      defaultToId ?? accounts.find((a) => a.id !== initialFrom)?.id ?? "",
    );
    setAmount("");
    setBookedAt(todayLocal());
    setDescription("");
  }, [open, defaultFromId, defaultToId, accounts]);

  function submit() {
    if (!fromId || !toId) {
      toast.error("Pick both accounts");
      return;
    }
    if (fromId === toId) {
      toast.error("From and To must be different accounts");
      return;
    }
    if (!/^\d+(\.\d{1,2})?$/.test(amount) || Number(amount) <= 0) {
      toast.error("Amount must be a positive number (max 2 decimals)");
      return;
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(bookedAt)) {
      toast.error("Date must be YYYY-MM-DD");
      return;
    }
    startTransition(async () => {
      const res = await fetch("/api/investments/move", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          fromAccountId: fromId,
          toAccountId: toId,
          amount,
          bookedAt,
          description: description.trim() || null,
        }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        toast.error(typeof data?.error === "string" ? data.error : "Move failed");
        return;
      }
      const data = (await res.json().catch(() => ({}))) as {
        amountEurMissing?: boolean;
        message?: string;
      };
      if (data.amountEurMissing) {
        toast.warning(data.message ?? "Move recorded, EUR amount pending FX backfill");
      } else {
        toast.success("Move recorded");
      }
      onOpenChange(false);
      router.refresh();
    });
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Move between investment accounts</DialogTitle>
          <DialogDescription>
            Records two transactions linked as a transfer. Cost basis shifts from the
            source account to the destination; aggregate stays the same.
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="grid gap-2">
              <Label htmlFor="from">From</Label>
              <NativeSelect
                id="from"
                value={fromId}
                onChange={(e) => setFromId(e.target.value)}
              >
                {accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </NativeSelect>
            </div>
            <div className="grid gap-2">
              <Label htmlFor="to">To</Label>
              <NativeSelect
                id="to"
                value={toId}
                onChange={(e) => setToId(e.target.value)}
              >
                {accounts
                  .filter((a) => a.id !== fromId)
                  .map((a) => (
                    <option key={a.id} value={a.id}>
                      {a.name}
                    </option>
                  ))}
              </NativeSelect>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="grid gap-2">
              <Label htmlFor="amount">Amount (EUR)</Label>
              <Input
                id="amount"
                type="number"
                step="0.01"
                inputMode="decimal"
                placeholder="100.00"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="bookedAt">Date</Label>
              <Input
                id="bookedAt"
                type="date"
                value={bookedAt}
                onChange={(e) => setBookedAt(e.target.value)}
              />
            </div>
          </div>
          <div className="grid gap-2">
            <Label htmlFor="description">Description (optional)</Label>
            <Input
              id="description"
              placeholder="monthly pension contribution"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
          </div>
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={pending}>
            Cancel
          </Button>
          <Button onClick={submit} disabled={pending}>
            {pending ? "Recording…" : "Record move"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
