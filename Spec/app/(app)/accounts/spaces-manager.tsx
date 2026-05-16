"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Plus, Trash2 } from "lucide-react";
import type { AccountSpace } from "@/db/schema";
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

export function SpacesManager({ spaces }: { spaces: AccountSpace[] }) {
  const router = useRouter();
  const [, startTransition] = useTransition();
  const [name, setName] = useState("");
  const [color, setColor] = useState("#10b981");
  const [creating, setCreating] = useState(false);

  async function create() {
    if (!name.trim()) return;
    setCreating(true);
    try {
      const res = await fetch("/api/spaces", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: name.trim(),
          color,
          sortOrder: spaces.length,
        }),
      });
      if (!res.ok) throw new Error("Failed");
      setName("");
      toast.success("Space created");
      startTransition(() => router.refresh());
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Failed");
    } finally {
      setCreating(false);
    }
  }

  async function remove(id: string) {
    if (!confirm("Delete this space? Accounts in it become unassigned (Individual).")) return;
    const res = await fetch(`/api/spaces/${id}`, { method: "DELETE" });
    if (!res.ok) {
      const body = await res.json().catch(() => null);
      toast.error(body?.error ?? "Failed");
      return;
    }
    toast.success("Deleted");
    startTransition(() => router.refresh());
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Spaces</CardTitle>
        <CardDescription>
          Partition accounts into views. Default is Individual. Shared / joint accounts can
          live in their own space; transfers across spaces are treated as separate
          expense/income, not as internal transfers.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <ul className="divide-y divide-border">
          {spaces.map((s) => (
            <li key={s.id} className="flex items-center gap-3 py-2">
              <span
                className="inline-block h-3 w-3 rounded-full"
                style={{ background: s.color ?? "#64748b" }}
              />
              <span className="flex-1 text-sm font-medium">{s.name}</span>
              {s.isDefault ? (
                <Badge variant="outline" className="text-[10px]">
                  default
                </Badge>
              ) : null}
              {s.isDefault ? null : (
                <Button
                  variant="ghost"
                  size="icon"
                  aria-label="Delete space"
                  onClick={() => remove(s.id)}
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              )}
            </li>
          ))}
        </ul>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-[1fr_auto_auto]">
          <div className="space-y-1">
            <Label className="text-xs">Name</Label>
            <Input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Shared with Marta"
            />
          </div>
          <div className="space-y-1">
            <Label className="text-xs">Color</Label>
            <Input
              type="color"
              value={color}
              onChange={(e) => setColor(e.target.value)}
              className="h-9 w-16 cursor-pointer p-1"
            />
          </div>
          <div className="flex items-end">
            <Button onClick={create} disabled={creating || !name.trim()}>
              <Plus className="h-4 w-4" />
              Add space
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
