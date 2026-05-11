"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Anchor, Plus, Trash2, Upload, Wallet } from "lucide-react";
import type { Account, AccountGroup, AccountSpace } from "@/db/schema";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
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
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { formatCurrency } from "@/lib/utils";

const UNGROUPED = "__none__";

type GroupKind = "cash" | "savings" | "investment" | "credit" | "other";

export interface AccountsManagerProps {
  accounts: Account[];
  groups: AccountGroup[];
  spaces: AccountSpace[];
  defaultSpaceId: string;
  nativeBalances: Record<string, string | null>;
  eurBalances: Record<string, number>;
}

export function AccountsManager({
  accounts,
  groups,
  spaces,
  defaultSpaceId,
  nativeBalances,
  eurBalances,
}: AccountsManagerProps) {
  const router = useRouter();
  const [, startTransition] = useTransition();

  const [groupName, setGroupName] = useState("");
  const [groupKind, setGroupKind] = useState<GroupKind>("cash");
  const [groupColor, setGroupColor] = useState("#3b82f6");
  const [creatingGroup, setCreatingGroup] = useState(false);

  const [manualName, setManualName] = useState("");
  const [manualInstitution, setManualInstitution] = useState("");
  const [manualCurrency, setManualCurrency] = useState("EUR");
  const [manualType, setManualType] = useState<"bank" | "broker" | "crypto">("bank");
  const [manualGroupId, setManualGroupId] = useState<string>(UNGROUPED);
  const [manualBalance, setManualBalance] = useState("");
  const [creatingAccount, setCreatingAccount] = useState(false);
  const [anchorAccount, setAnchorAccount] = useState<Account | null>(null);
  const [importAccount, setImportAccount] = useState<Account | null>(null);

  const accountsByGroup = useMemo(() => {
    const map = new Map<string | null, Account[]>();
    for (const a of accounts) {
      if (a.archived) continue;
      const key = a.groupId ?? null;
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(a);
    }
    return map;
  }, [accounts]);

  async function createGroup() {
    if (!groupName.trim()) return;
    setCreatingGroup(true);
    try {
      const res = await fetch("/api/account-groups", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: groupName.trim(),
          kind: groupKind,
          color: groupColor,
          sortOrder: groups.length,
        }),
      });
      if (!res.ok) throw new Error("Failed");
      setGroupName("");
      toast.success("Group created");
      startTransition(() => router.refresh());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setCreatingGroup(false);
    }
  }

  async function deleteGroup(id: string) {
    if (!confirm("Delete this group? Its accounts will be ungrouped.")) return;
    const res = await fetch(`/api/account-groups/${id}`, { method: "DELETE" });
    if (!res.ok) {
      toast.error("Failed");
      return;
    }
    toast.success("Deleted");
    startTransition(() => router.refresh());
  }

  async function assignGroup(accountId: string, value: string) {
    const res = await fetch(`/api/accounts/${accountId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ groupId: value === UNGROUPED ? null : value }),
    });
    if (!res.ok) {
      toast.error("Failed");
      return;
    }
    startTransition(() => router.refresh());
  }

  async function assignSpace(accountId: string, value: string) {
    const res = await fetch(`/api/accounts/${accountId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ spaceId: value }),
    });
    if (!res.ok) {
      toast.error("Failed");
      return;
    }
    startTransition(() => router.refresh());
  }

  async function toggleExcluded(accountId: string, excluded: boolean) {
    const res = await fetch(`/api/accounts/${accountId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ excluded }),
    });
    if (!res.ok) {
      toast.error("Failed");
      return;
    }
    toast.success(excluded ? "Excluded" : "Included");
    startTransition(() => router.refresh());
  }

  async function createManualAccount() {
    if (!manualName.trim() || !manualInstitution.trim()) return;
    setCreatingAccount(true);
    try {
      const res = await fetch("/api/accounts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: manualName.trim(),
          institution: manualInstitution.trim(),
          type: manualType,
          currency: manualCurrency.trim().toUpperCase(),
          groupId: manualGroupId === UNGROUPED ? null : manualGroupId,
          balance: manualBalance.trim() || undefined,
        }),
      });
      if (!res.ok) throw new Error("Failed");
      setManualName("");
      setManualInstitution("");
      setManualBalance("");
      toast.success("Account created");
      startTransition(() => router.refresh());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setCreatingAccount(false);
    }
  }

  async function deleteAccount(id: string) {
    if (!confirm("Delete this account and all its transactions?")) return;
    const res = await fetch(`/api/accounts/${id}`, { method: "DELETE" });
    if (!res.ok) {
      toast.error("Failed");
      return;
    }
    toast.success("Deleted");
    startTransition(() => router.refresh());
  }

  function totalForGroup(items: Account[]): number {
    return items.reduce((sum, a) => sum + (eurBalances[a.id] ?? 0), 0);
  }

  return (
    <div className="space-y-6">
      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>New group</CardTitle>
            <CardDescription>Buckets like Cash, Savings, Investments.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div className="space-y-1">
                <Label className="text-xs">Name</Label>
                <Input
                  value={groupName}
                  onChange={(e) => setGroupName(e.target.value)}
                  placeholder="e.g. Savings"
                />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Kind</Label>
                <Select
                  value={groupKind}
                  onValueChange={(v) => setGroupKind(v as GroupKind)}
                >
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="cash">Cash</SelectItem>
                    <SelectItem value="savings">Savings</SelectItem>
                    <SelectItem value="investment">Investment</SelectItem>
                    <SelectItem value="credit">Credit</SelectItem>
                    <SelectItem value="other">Other</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Color</Label>
                <Input
                  type="color"
                  value={groupColor}
                  onChange={(e) => setGroupColor(e.target.value)}
                  className="h-9 w-16 cursor-pointer p-1"
                />
              </div>
              <div className="flex items-end">
                <Button
                  onClick={createGroup}
                  disabled={creatingGroup || !groupName.trim()}
                  className="w-full"
                >
                  <Plus className="h-4 w-4" />
                  Add group
                </Button>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>New manual account</CardTitle>
            <CardDescription>
              For cash, savings, or anything not synced from a bank.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <div className="space-y-1">
                <Label className="text-xs">Name</Label>
                <Input
                  value={manualName}
                  onChange={(e) => setManualName(e.target.value)}
                  placeholder="e.g. Cash wallet"
                />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Institution</Label>
                <Input
                  value={manualInstitution}
                  onChange={(e) => setManualInstitution(e.target.value)}
                  placeholder="e.g. Wallet"
                />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Currency</Label>
                <Input
                  value={manualCurrency}
                  onChange={(e) => setManualCurrency(e.target.value)}
                  maxLength={3}
                />
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Type</Label>
                <Select
                  value={manualType}
                  onValueChange={(v) =>
                    setManualType(v as "bank" | "broker" | "crypto")
                  }
                >
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="bank">Bank</SelectItem>
                    <SelectItem value="broker">Broker</SelectItem>
                    <SelectItem value="crypto">Crypto</SelectItem>
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Group</Label>
                <Select value={manualGroupId} onValueChange={setManualGroupId}>
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value={UNGROUPED}>Ungrouped</SelectItem>
                    {groups.map((g) => (
                      <SelectItem key={g.id} value={g.id}>
                        {g.name}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label className="text-xs">Opening balance</Label>
                <Input
                  type="number"
                  value={manualBalance}
                  onChange={(e) => setManualBalance(e.target.value)}
                  placeholder="0.00"
                />
              </div>
            </div>
            <Button
              onClick={createManualAccount}
              disabled={creatingAccount || !manualName.trim() || !manualInstitution.trim()}
            >
              <Plus className="h-4 w-4" />
              Add account
            </Button>
          </CardContent>
        </Card>
      </div>

      {groups.length === 0 && accountsByGroup.size === 0 ? (
        <div className="rounded-lg border border-dashed border-border p-10 text-center">
          <Wallet className="mx-auto h-6 w-6 text-muted-foreground" />
          <p className="mt-3 text-sm font-medium">No accounts yet</p>
          <p className="text-sm text-muted-foreground">
            Create a group and add a manual account, or connect a bank.
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          {groups.map((g) => {
            const items = accountsByGroup.get(g.id) ?? [];
            const total = totalForGroup(items);
            return (
              <Card key={g.id}>
                <CardHeader className="flex flex-row items-center justify-between">
                  <div className="flex items-center gap-3">
                    <span
                      className="inline-block h-3 w-3 rounded-full"
                      style={{ background: g.color ?? "#3b82f6" }}
                    />
                    <div>
                      <CardTitle className="text-base">{g.name}</CardTitle>
                      <CardDescription className="capitalize">{g.kind}</CardDescription>
                    </div>
                  </div>
                  <div className="flex items-center gap-3">
                    <p className="tabular text-sm font-medium">
                      {formatCurrency(total, "EUR")}
                    </p>
                    <Button
                      variant="ghost"
                      size="icon"
                      onClick={() => deleteGroup(g.id)}
                      aria-label="Delete group"
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                </CardHeader>
                <CardContent>
                  <AccountList
                    items={items}
                    groups={groups}
                    spaces={spaces}
                    defaultSpaceId={defaultSpaceId}
                    nativeBalances={nativeBalances}
                    onAssign={assignGroup}
                    onAssignSpace={assignSpace}
                    onToggleExcluded={toggleExcluded}
                    onDelete={deleteAccount}
                    onSetAnchor={setAnchorAccount}
                    onImport={setImportAccount}
                  />
                </CardContent>
              </Card>
            );
          })}

          <Card>
            <CardHeader>
              <CardTitle className="text-base">Ungrouped</CardTitle>
              <CardDescription>Accounts not assigned to any group.</CardDescription>
            </CardHeader>
            <CardContent>
              <AccountList
                items={accountsByGroup.get(null) ?? []}
                groups={groups}
                spaces={spaces}
                defaultSpaceId={defaultSpaceId}
                nativeBalances={nativeBalances}
                onAssign={assignGroup}
                onAssignSpace={assignSpace}
                onToggleExcluded={toggleExcluded}
                onDelete={deleteAccount}
                onSetAnchor={setAnchorAccount}
                onImport={setImportAccount}
              />
            </CardContent>
          </Card>
        </div>
      )}
      <AnchorDialog
        account={anchorAccount}
        onOpenChange={(open) => {
          if (!open) setAnchorAccount(null);
        }}
        onSaved={() => startTransition(() => router.refresh())}
      />
      <ImportCsvDialog
        account={importAccount}
        onOpenChange={(open) => {
          if (!open) setImportAccount(null);
        }}
        onImported={() => startTransition(() => router.refresh())}
      />
    </div>
  );
}

function AccountList({
  items,
  groups,
  spaces,
  defaultSpaceId,
  nativeBalances,
  onAssign,
  onAssignSpace,
  onToggleExcluded,
  onDelete,
  onSetAnchor,
  onImport,
}: {
  items: Account[];
  groups: AccountGroup[];
  spaces: AccountSpace[];
  defaultSpaceId: string;
  nativeBalances: Record<string, string | null>;
  onAssign: (accountId: string, groupId: string) => void;
  onAssignSpace: (accountId: string, spaceId: string) => void;
  onToggleExcluded: (accountId: string, excluded: boolean) => void;
  onDelete: (id: string) => void;
  onSetAnchor: (a: Account) => void;
  onImport: (a: Account) => void;
}) {
  if (items.length === 0) {
    return <p className="text-sm text-muted-foreground">No accounts in this group.</p>;
  }
  return (
    <ul className="divide-y divide-border">
      {items.map((a) => (
        <li key={a.id} className="flex items-center gap-3 py-2">
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium">{a.name}</p>
            <p className="truncate text-xs text-muted-foreground">
              {a.institution}
              {a.iban ? ` · ${a.iban.slice(-6)}` : null}
              <Badge variant="outline" className="ml-2 text-[10px] uppercase">
                {a.type}
              </Badge>
              {a.connectionId ? null : (
                <Badge variant="secondary" className="ml-2 text-[10px]">
                  manual
                </Badge>
              )}
              {a.balanceAnchor && a.balanceAnchorAt ? (
                <Badge variant="outline" className="ml-2 text-[10px]">
                  anchored {new Date(a.balanceAnchorAt).toISOString().slice(0, 10)}
                </Badge>
              ) : null}
              {a.excluded ? (
                <Badge variant="secondary" className="ml-2 text-[10px]">
                  excluded
                </Badge>
              ) : null}
            </p>
          </div>
          <p className="tabular text-sm">
            {nativeBalances[a.id]
              ? formatCurrency(Number(nativeBalances[a.id]), a.currency)
              : "—"}
          </p>
          <Button
            variant="ghost"
            size="icon"
            aria-label="Set current balance"
            onClick={() => onSetAnchor(a)}
            title="Set current balance (anchor)"
          >
            <Anchor className="h-4 w-4" />
          </Button>
          {a.connectionId ? null : (
            <Button
              variant="ghost"
              size="icon"
              aria-label="Import CSV statement"
              onClick={() => onImport(a)}
              title="Import CSV statement"
            >
              <Upload className="h-4 w-4" />
            </Button>
          )}
          <Select
            value={a.spaceId ?? defaultSpaceId}
            onValueChange={(v) => onAssignSpace(a.id, v)}
          >
            <SelectTrigger className="w-[130px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {spaces.map((s) => (
                <SelectItem key={s.id} value={s.id}>
                  {s.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={a.groupId ?? UNGROUPED} onValueChange={(v) => onAssign(a.id, v)}>
            <SelectTrigger className="w-[130px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value={UNGROUPED}>Ungrouped</SelectItem>
              {groups.map((g) => (
                <SelectItem key={g.id} value={g.id}>
                  {g.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <div className="flex items-center gap-1" title="Exclude from all totals">
            <Switch
              checked={!a.excluded}
              onCheckedChange={(v) => onToggleExcluded(a.id, !v)}
              aria-label="Toggle inclusion"
            />
          </div>
          {a.connectionId ? null : (
            <Button
              variant="ghost"
              size="icon"
              aria-label="Delete account"
              onClick={() => onDelete(a.id)}
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          )}
        </li>
      ))}
    </ul>
  );
}

function AnchorDialog({
  account,
  onOpenChange,
  onSaved,
}: {
  account: Account | null;
  onOpenChange: (open: boolean) => void;
  onSaved: () => void;
}) {
  const [amount, setAmount] = useState("");
  const [dateStr, setDateStr] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!account) return;
    setAmount(
      account.balanceAnchor != null
        ? String(account.balanceAnchor)
        : account.balance ?? "",
    );
    const d = account.balanceAnchorAt ? new Date(account.balanceAnchorAt) : new Date();
    const off = d.getTimezoneOffset();
    const local = new Date(d.getTime() - off * 60_000);
    setDateStr(local.toISOString().slice(0, 16));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [account?.id]);

  if (!account) return null;

  async function submit(clear = false) {
    if (!account) return;
    setSaving(true);
    try {
      const body: Record<string, unknown> = {};
      if (clear) {
        body.balanceAnchor = null;
        body.balanceAnchorAt = null;
      } else {
        const n = Number(amount);
        if (!Number.isFinite(n)) {
          toast.error("Invalid amount");
          setSaving(false);
          return;
        }
        body.balanceAnchor = n.toFixed(4);
        body.balanceAnchorAt = new Date(dateStr).toISOString();
      }
      const res = await fetch(`/api/accounts/${account.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!res.ok) throw new Error("Failed");
      toast.success(clear ? "Anchor cleared" : "Balance anchored");
      onSaved();
      onOpenChange(false);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setSaving(false);
    }
  }

  const hasAnchor = account.balanceAnchor != null && account.balanceAnchorAt != null;

  return (
    <Dialog open={!!account} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Set current balance — {account.name}</DialogTitle>
          <DialogDescription>
            Anchor the real balance at a specific moment. Going forward, the displayed
            balance will be anchor + sum of transactions after this date. Older
            transactions stay in the DB but stop affecting the balance.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          <div className="space-y-1">
            <Label className="text-xs">Amount ({account.currency})</Label>
            <Input
              type="number"
              step="0.01"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-xs">As of</Label>
            <Input
              type="datetime-local"
              value={dateStr}
              onChange={(e) => setDateStr(e.target.value)}
            />
          </div>
        </div>
        <DialogFooter>
          {hasAnchor ? (
            <Button
              variant="outline"
              onClick={() => submit(true)}
              disabled={saving}
            >
              Clear anchor
            </Button>
          ) : null}
          <Button onClick={() => submit(false)} disabled={saving || !amount || !dateStr}>
            {saving ? "Saving…" : "Save"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

interface ImportResultDisplay {
  parsed: number;
  inserted: number;
  skippedTransfer: number;
  skippedDuplicate: number;
  errors?: string[];
  postProcess?: {
    fxBackfilled: number;
    categorized: number;
    routedMirrors: number;
    transfersMatched: number;
  };
}

function ImportCsvDialog({
  account,
  onOpenChange,
  onImported,
}: {
  account: Account | null;
  onOpenChange: (open: boolean) => void;
  onImported: () => void;
}) {
  const [file, setFile] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<ImportResultDisplay | null>(null);

  useEffect(() => {
    if (!account) {
      setFile(null);
      setResult(null);
      setSubmitting(false);
    }
  }, [account]);

  if (!account) return null;

  async function submit() {
    if (!file || !account) return;
    setSubmitting(true);
    try {
      const fd = new FormData();
      fd.append("file", file);
      const res = await fetch(`/api/accounts/${account.id}/import-csv`, {
        method: "POST",
        body: fd,
      });
      const body = (await res.json().catch(() => null)) as
        | (ImportResultDisplay & { error?: string })
        | null;
      if (!res.ok) {
        toast.error(body?.error ?? "Import failed");
        return;
      }
      setResult(body);
      const summary = `Imported ${body?.inserted ?? 0} · skipped ${body?.skippedDuplicate ?? 0} dup, ${body?.skippedTransfer ?? 0} transfer`;
      toast.success(summary);
      onImported();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Import failed");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <Dialog open={!!account} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Import CSV — {account.name}</DialogTitle>
          <DialogDescription>
            Upload a Revolut statement CSV. CARD_PAYMENT rows are inserted as debits.
            TRANSFER rows are skipped (handled by transfer routes). Re-uploading the
            same file is safe — duplicates are detected and skipped.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          <div className="space-y-1">
            <Label className="text-xs">CSV file</Label>
            <Input
              type="file"
              accept=".csv,text/csv"
              onChange={(e) => {
                setFile(e.target.files?.[0] ?? null);
                setResult(null);
              }}
            />
          </div>
          {result ? (
            <div className="rounded-md border border-border bg-muted/30 p-3 text-xs">
              <p className="font-medium">Import summary</p>
              <ul className="mt-1 space-y-0.5 text-muted-foreground">
                <li>Parsed: {result.parsed}</li>
                <li>Inserted: {result.inserted}</li>
                <li>Skipped (transfer rows): {result.skippedTransfer}</li>
                <li>Skipped (duplicates): {result.skippedDuplicate}</li>
                {result.postProcess ? (
                  <>
                    <li>FX backfilled: {result.postProcess.fxBackfilled}</li>
                    <li>Categorised by rules: {result.postProcess.categorized}</li>
                    <li>Routed mirrors created: {result.postProcess.routedMirrors}</li>
                    <li>Transfers matched: {result.postProcess.transfersMatched}</li>
                  </>
                ) : null}
                {result.errors && result.errors.length > 0 ? (
                  <li className="text-destructive">Errors: {result.errors.length}</li>
                ) : null}
              </ul>
            </div>
          ) : null}
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={submitting}>
            {result ? "Close" : "Cancel"}
          </Button>
          <Button onClick={submit} disabled={submitting || !file}>
            {submitting ? "Importing…" : "Import"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
