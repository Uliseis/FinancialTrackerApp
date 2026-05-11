"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Plus, Trash2, Wand2 } from "lucide-react";
import type { TransferRoute } from "@/db/schema";
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
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  RULE_FIELDS,
  RULE_MATCH_TYPES,
  type RuleField,
  type RuleMatch,
} from "@/lib/rules";

interface AccountOption {
  id: string;
  name: string;
  currency: string;
  institution: string;
  isManual: boolean;
}

interface ManualOption {
  id: string;
  name: string;
  currency: string;
}

const ANY_SOURCE = "__any__";
const ANY_DIRECTION = "__any__";

export interface TransferRoutesManagerProps {
  routes: TransferRoute[];
  accounts: AccountOption[];
  manualAccounts: ManualOption[];
}

export function TransferRoutesManager({
  routes,
  accounts,
  manualAccounts,
}: TransferRoutesManagerProps) {
  const router = useRouter();
  const [, startTransition] = useTransition();

  const [pattern, setPattern] = useState("");
  const [field, setField] = useState<RuleField>("description");
  const [matchType, setMatchType] = useState<RuleMatch>("contains");
  const [sourceAccountId, setSourceAccountId] = useState<string>(ANY_SOURCE);
  const [targetAccountId, setTargetAccountId] = useState<string>(
    manualAccounts[0]?.id ?? "",
  );
  const [direction, setDirection] = useState<string>(ANY_DIRECTION);
  const [priority, setPriority] = useState(0);
  const [creating, setCreating] = useState(false);

  const accountById = useMemo(
    () => new Map(accounts.map((a) => [a.id, a])),
    [accounts],
  );

  async function createRoute() {
    if (!pattern.trim() || !targetAccountId) return;
    setCreating(true);
    try {
      const res = await fetch("/api/transfer-routes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          pattern: pattern.trim(),
          field,
          matchType,
          sourceAccountId: sourceAccountId === ANY_SOURCE ? null : sourceAccountId,
          targetAccountId,
          direction: direction === ANY_DIRECTION ? null : direction,
          priority,
        }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        throw new Error(data?.error?.formErrors?.join(", ") ?? data?.error ?? "Failed");
      }
      setPattern("");
      toast.success("Route added");
      startTransition(() => router.refresh());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setCreating(false);
    }
  }

  async function deleteRoute(id: string) {
    if (!confirm("Delete this route? Existing mirrors stay until you also delete them.")) return;
    const res = await fetch(`/api/transfer-routes/${id}`, { method: "DELETE" });
    if (!res.ok) {
      toast.error("Delete failed");
      return;
    }
    toast.success("Deleted");
    startTransition(() => router.refresh());
  }

  async function toggleEnabled(route: TransferRoute) {
    const res = await fetch(`/api/transfer-routes/${route.id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ enabled: !route.enabled }),
    });
    if (!res.ok) {
      toast.error("Failed");
      return;
    }
    startTransition(() => router.refresh());
  }

  async function backfill(id?: string) {
    const url = id ? `/api/transfer-routes/${id}/backfill` : "/api/transfer-routes/backfill";
    const p = (async () => {
      const res = await fetch(url, { method: "POST" });
      if (!res.ok) throw new Error("Failed");
      return (await res.json()) as { scanned: number; mirroredCreated: number };
    })();
    toast.promise(p, {
      loading: id ? "Applying this route…" : "Applying all routes…",
      success: (r) => `Created ${r.mirroredCreated} mirror${r.mirroredCreated === 1 ? "" : "s"} (scanned ${r.scanned})`,
      error: "Backfill failed",
    });
    try {
      await p;
      startTransition(() => router.refresh());
    } catch {}
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader className="flex flex-row items-start justify-between gap-3">
          <div>
            <CardTitle>New route</CardTitle>
            <CardDescription>
              When a source transaction matches the pattern, a mirror is created on the
              target account so the money stays in your net worth instead of being lost
              as an expense.
            </CardDescription>
          </div>
          <Button size="sm" variant="outline" onClick={() => backfill()}>
            <Wand2 className="h-4 w-4" />
            Run all routes
          </Button>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
            <div className="space-y-1">
              <Label className="text-xs">Pattern</Label>
              <Input
                value={pattern}
                onChange={(e) => setPattern(e.target.value)}
                placeholder="e.g. To Instant Access Savings"
              />
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Target account</Label>
              <Select value={targetAccountId} onValueChange={setTargetAccountId}>
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Pick a manual account" />
                </SelectTrigger>
                <SelectContent>
                  {manualAccounts.length === 0 ? (
                    <SelectItem value="__none" disabled>
                      No manual accounts — create one first
                    </SelectItem>
                  ) : (
                    manualAccounts.map((a) => (
                      <SelectItem key={a.id} value={a.id}>
                        {a.name}
                        <span className="ml-2 text-xs text-muted-foreground">
                          {a.currency}
                        </span>
                      </SelectItem>
                    ))
                  )}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Source account (optional)</Label>
              <Select value={sourceAccountId} onValueChange={setSourceAccountId}>
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={ANY_SOURCE}>Any account</SelectItem>
                  {accounts.map((a) => (
                    <SelectItem key={a.id} value={a.id}>
                      {a.name}
                      <span className="ml-2 text-xs text-muted-foreground">
                        {a.institution}
                      </span>
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Field</Label>
              <Select value={field} onValueChange={(v) => setField(v as RuleField)}>
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {RULE_FIELDS.map((f) => (
                    <SelectItem key={f} value={f} className="capitalize">
                      {f}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Match</Label>
              <Select value={matchType} onValueChange={(v) => setMatchType(v as RuleMatch)}>
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {RULE_MATCH_TYPES.map((m) => (
                    <SelectItem key={m} value={m} className="capitalize">
                      {m}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Direction</Label>
              <Select value={direction} onValueChange={setDirection}>
                <SelectTrigger className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value={ANY_DIRECTION}>Either</SelectItem>
                  <SelectItem value="debit">Debit (money leaving)</SelectItem>
                  <SelectItem value="credit">Credit (money coming back)</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label className="text-xs">Priority</Label>
              <Input
                type="number"
                value={priority}
                onChange={(e) => setPriority(Number(e.target.value || 0))}
              />
            </div>
            <div className="flex items-end sm:col-span-2 lg:col-span-3">
              <Button
                onClick={createRoute}
                disabled={creating || !pattern.trim() || !targetAccountId}
              >
                <Plus className="h-4 w-4" />
                Add route
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Existing routes</CardTitle>
          <CardDescription>
            Ordered by priority (highest first), then creation time. First match wins.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="rounded-lg border border-border">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead>Pattern</TableHead>
                  <TableHead>Field</TableHead>
                  <TableHead>Match</TableHead>
                  <TableHead>Source</TableHead>
                  <TableHead>Target</TableHead>
                  <TableHead>Direction</TableHead>
                  <TableHead className="text-right">Priority</TableHead>
                  <TableHead className="w-24" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {routes.length === 0 ? (
                  <TableRow className="hover:bg-transparent">
                    <TableCell
                      colSpan={8}
                      className="py-6 text-center text-sm text-muted-foreground"
                    >
                      No routes yet. Create a manual account for each Revolut pocket
                      (Savings, Credit Card, EUR…) and add a pattern that matches the
                      bank-feed description.
                    </TableCell>
                  </TableRow>
                ) : (
                  routes.map((r) => {
                    const target = accountById.get(r.targetAccountId);
                    const source = r.sourceAccountId
                      ? accountById.get(r.sourceAccountId)
                      : null;
                    return (
                      <TableRow key={r.id} className={r.enabled ? "" : "opacity-60"}>
                        <TableCell className="text-sm font-medium">{r.pattern}</TableCell>
                        <TableCell className="text-xs capitalize">{r.field}</TableCell>
                        <TableCell className="text-xs capitalize">{r.matchType}</TableCell>
                        <TableCell className="text-xs">
                          {source ? source.name : <span className="text-muted-foreground">any</span>}
                        </TableCell>
                        <TableCell className="text-xs">
                          <Badge variant="outline">{target?.name ?? "—"}</Badge>
                        </TableCell>
                        <TableCell className="text-xs capitalize">
                          {r.direction ?? <span className="text-muted-foreground">either</span>}
                        </TableCell>
                        <TableCell className="tabular text-right text-sm">{r.priority}</TableCell>
                        <TableCell className="text-right">
                          <div className="flex items-center justify-end gap-1">
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => toggleEnabled(r)}
                            >
                              {r.enabled ? "Disable" : "Enable"}
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              aria-label="Apply route"
                              onClick={() => backfill(r.id)}
                            >
                              <Wand2 className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost"
                              size="icon"
                              aria-label="Delete route"
                              onClick={() => deleteRoute(r.id)}
                            >
                              <Trash2 className="h-4 w-4" />
                            </Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    );
                  })
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
