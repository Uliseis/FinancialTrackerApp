import Link from "next/link";
import { db } from "@/lib/db";
import { accounts, transactions } from "@/db/schema";
import { desc, eq } from "drizzle-orm";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
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

export const dynamic = "force-dynamic";

const PAGE_SIZE = 100;

export default async function TransactionsPage() {
  const rows = await db
    .select({
      id: transactions.id,
      bookedAt: transactions.bookedAt,
      amount: transactions.amount,
      currency: transactions.currency,
      direction: transactions.direction,
      description: transactions.description,
      counterparty: transactions.counterparty,
      accountName: accounts.name,
      institution: accounts.institution,
    })
    .from(transactions)
    .leftJoin(accounts, eq(transactions.accountId, accounts.id))
    .orderBy(desc(transactions.bookedAt))
    .limit(PAGE_SIZE);

  return (
    <main className="container py-10">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Transactions</h1>
          <p className="text-sm text-[var(--color-muted-foreground)]">
            Most recent {PAGE_SIZE} synced rows.
          </p>
        </div>
        <Button asChild variant="outline">
          <Link href="/">Back</Link>
        </Button>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Recent</CardTitle>
        </CardHeader>
        <CardContent>
          {rows.length === 0 ? (
            <p className="text-sm text-[var(--color-muted-foreground)]">
              No transactions yet. Connect a bank to start syncing.
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Date</TableHead>
                  <TableHead>Account</TableHead>
                  <TableHead>Description</TableHead>
                  <TableHead>Counterparty</TableHead>
                  <TableHead className="text-right">Amount</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((r) => (
                  <TableRow key={r.id}>
                    <TableCell>{formatDate(r.bookedAt)}</TableCell>
                    <TableCell>
                      <p className="text-sm font-medium">{r.accountName ?? "—"}</p>
                      <p className="text-xs text-[var(--color-muted-foreground)]">
                        {r.institution}
                      </p>
                    </TableCell>
                    <TableCell className="max-w-md truncate">
                      {r.description ?? ""}
                    </TableCell>
                    <TableCell>{r.counterparty ?? ""}</TableCell>
                    <TableCell className="text-right">
                      <Badge
                        variant={r.direction === "credit" ? "success" : "secondary"}
                      >
                        {formatCurrency(parseFloat(r.amount), r.currency)}
                      </Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </main>
  );
}
