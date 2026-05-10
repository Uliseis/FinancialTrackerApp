import { and, eq } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  accounts,
  connections,
  syncRuns,
  transactions,
  type NewAccount,
  type NewTransaction,
} from "@/db/schema";
import {
  GoCardlessClient,
  pickBookingDate,
  pickCounterparty,
  pickDescription,
  pickExternalId,
} from "@/lib/gocardless";

export interface SyncResult {
  connectionId: string;
  accountsTouched: number;
  transactionsInserted: number;
  errors: string[];
}

export async function syncGocardlessConnection(
  connectionId: string,
): Promise<SyncResult> {
  const result: SyncResult = {
    connectionId,
    accountsTouched: 0,
    transactionsInserted: 0,
    errors: [],
  };

  const [conn] = await db
    .select()
    .from(connections)
    .where(eq(connections.id, connectionId));
  if (!conn) throw new Error(`Connection ${connectionId} not found`);
  if (conn.connector !== "gocardless") {
    throw new Error(`Connection ${connectionId} is not a gocardless connection`);
  }
  if (!conn.requisitionId) {
    throw new Error(`Connection ${connectionId} has no requisition_id`);
  }

  const [run] = await db
    .insert(syncRuns)
    .values({ connector: "gocardless", connectionId })
    .returning();

  const client = new GoCardlessClient();

  try {
    const requisition = await client.getRequisition(conn.requisitionId);
    const accountIds = requisition.accounts ?? [];
    result.accountsTouched = accountIds.length;

    for (const externalAccountId of accountIds) {
      try {
        const details = await client.getAccountDetails(externalAccountId);
        const balances = await client.getAccountBalances(externalAccountId);
        const interim =
          balances.balances.find((b) =>
            ["interimAvailable", "interimBooked", "expected"].includes(b.balanceType),
          ) ?? balances.balances[0];

        const accountValues: NewAccount = {
          connectionId,
          externalId: externalAccountId,
          type: "bank",
          institution: conn.institutionName ?? conn.institutionId ?? "Unknown",
          name:
            details.account.name ??
            details.account.product ??
            details.account.iban ??
            "Account",
          currency: details.account.currency ?? interim?.balanceAmount.currency ?? "EUR",
          iban: details.account.iban ?? null,
          balance: interim ? interim.balanceAmount.amount : null,
          balanceUpdatedAt: new Date(),
          metadata: details.account as unknown as Record<string, unknown>,
        };

        const [account] = await db
          .insert(accounts)
          .values(accountValues)
          .onConflictDoUpdate({
            target: [accounts.connectionId, accounts.externalId],
            set: {
              name: accountValues.name,
              currency: accountValues.currency,
              iban: accountValues.iban,
              balance: accountValues.balance,
              balanceUpdatedAt: accountValues.balanceUpdatedAt,
              metadata: accountValues.metadata,
            },
          })
          .returning();

        const tx = await client.getAccountTransactions(externalAccountId);
        const booked = tx.transactions.booked ?? [];

        for (const t of booked) {
          const externalId = pickExternalId(
            t,
            `${externalAccountId}:${t.bookingDate ?? t.valueDate ?? ""}:${t.transactionAmount.amount}`,
          );
          const amount = parseFloat(t.transactionAmount.amount);
          const direction = amount < 0 ? "debit" : "credit";

          const txValues: NewTransaction = {
            accountId: account.id,
            externalId,
            bookedAt: pickBookingDate(t),
            valueAt: t.valueDateTime
              ? new Date(t.valueDateTime)
              : t.valueDate
                ? new Date(t.valueDate)
                : null,
            amount: t.transactionAmount.amount,
            currency: t.transactionAmount.currency,
            direction,
            description: pickDescription(t) || null,
            counterparty: pickCounterparty(t),
            raw: t as unknown as Record<string, unknown>,
          };

          const inserted = await db
            .insert(transactions)
            .values(txValues)
            .onConflictDoNothing({
              target: [transactions.accountId, transactions.externalId],
            })
            .returning({ id: transactions.id });
          result.transactionsInserted += inserted.length;
        }
      } catch (err) {
        const msg =
          err instanceof Error ? `${externalAccountId}: ${err.message}` : String(err);
        result.errors.push(msg);
      }
    }

    await db
      .update(connections)
      .set({
        status: result.errors.length > 0 ? "error" : "active",
        lastSyncAt: new Date(),
        lastError: result.errors.length > 0 ? result.errors.join("; ") : null,
        updatedAt: new Date(),
      })
      .where(eq(connections.id, connectionId));

    await db
      .update(syncRuns)
      .set({
        finishedAt: new Date(),
        status: result.errors.length > 0 ? "partial" : "ok",
        insertedTransactions: result.transactionsInserted,
        error: result.errors.length > 0 ? result.errors.join("; ") : null,
      })
      .where(eq(syncRuns.id, run.id));

    return result;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await db
      .update(connections)
      .set({
        status: "error",
        lastError: message,
        updatedAt: new Date(),
      })
      .where(eq(connections.id, connectionId));
    await db
      .update(syncRuns)
      .set({
        finishedAt: new Date(),
        status: "error",
        error: message,
      })
      .where(eq(syncRuns.id, run.id));
    throw err;
  }
}

export async function syncAllGocardlessConnections(): Promise<SyncResult[]> {
  const rows = await db
    .select()
    .from(connections)
    .where(and(eq(connections.connector, "gocardless")));
  const out: SyncResult[] = [];
  for (const row of rows) {
    if (row.status === "revoked") continue;
    try {
      out.push(await syncGocardlessConnection(row.id));
    } catch (err) {
      out.push({
        connectionId: row.id,
        accountsTouched: 0,
        transactionsInserted: 0,
        errors: [err instanceof Error ? err.message : String(err)],
      });
    }
  }
  return out;
}
