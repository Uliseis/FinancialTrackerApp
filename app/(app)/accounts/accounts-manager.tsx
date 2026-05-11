"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Plus, Trash2, Wallet } from "lucide-react";
import type { Account, AccountGroup } from "@/db/schema";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
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
import { formatCurrency } from "@/lib/utils";

const UNGROUPED = "__none__";

type GroupKind = "cash" | "savings" | "investment" | "credit" | "other";

export interface AccountsManagerProps {
  accounts: Account[];
  groups: AccountGroup[];
}

export function AccountsManager({ accounts, groups }: AccountsManagerProps) {
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
    return items.reduce((sum, a) => sum + (a.balance ? Number(a.balance) : 0), 0);
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
                    onAssign={assignGroup}
                    onDelete={deleteAccount}
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
                onAssign={assignGroup}
                onDelete={deleteAccount}
              />
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}

function AccountList({
  items,
  groups,
  onAssign,
  onDelete,
}: {
  items: Account[];
  groups: AccountGroup[];
  onAssign: (accountId: string, groupId: string) => void;
  onDelete: (id: string) => void;
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
            </p>
          </div>
          <p className="tabular text-sm">
            {a.balance ? formatCurrency(Number(a.balance), a.currency) : "—"}
          </p>
          <Select value={a.groupId ?? UNGROUPED} onValueChange={(v) => onAssign(a.id, v)}>
            <SelectTrigger className="w-[140px]">
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
