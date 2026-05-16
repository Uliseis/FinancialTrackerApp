import { and, eq, inArray, isNull, lt } from "drizzle-orm";
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
  EnableBankingClient,
  EnableBankingError,
  ibanOf,
  pickBookingDate,
  pickCounterparty,
  pickDescription,
  pickExternalId,
  pickValueDate,
  preferredBalance,
  sessionAccountsOf,
  signedAmount,
  type EbTransaction,
} from "@/lib/enablebanking";
import { applyRulesToTransactions } from "@/lib/categorize";
import { detectTransfers, repairTransferGroups } from "@/lib/transfers";
import { backfillTransactionEurAmounts } from "@/lib/fx";
import { applyTransferRoutes } from "@/lib/transfer-routes";
import { getDefaultSpaceId } from "@/lib/spaces";
import {
  assertTransferInvariants,
  formatInvariantViolations,
} from "@/lib/transfer-invariants";

const STALE_RUN_MS = 10 * 60 * 1000;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidUid(uid: unknown): uid is string {
  if (typeof uid !== "string") return false;
  if (uid.length === 0) return false;
  if (uid === "undefined" || uid === "null") return false;
  return UUID_RE.test(uid);
}

async function reapStaleSyncRuns(): Promise<void> {
  const threshold = new Date(Date.now() - STALE_RUN_MS);
  await db
    .update(syncRuns)
    .set({
      status: "error",
      finishedAt: new Date(),
      error: "abandoned",
    })
    .where(
      and(
        eq(syncRuns.status, "running"),
        lt(syncRuns.startedAt, threshold),
        isNull(syncRuns.finishedAt),
      ),
    );
}

export interface SyncResult {
  connectionId: string;
  accountsTouched: number;
  transactionsInserted: number;
  errors: string[];
  postProcess?: {
    fxBackfilled: number;
    fxSkipped: number;
    categorized: number;
    routedMirrors: number;
    transfersMatched: number;
  };
}

const TX_PAGE_LIMIT = 50;
const TX_LOOKBACK_DAYS = 730;
const TX_INCREMENTAL_OVERLAP_DAYS = 7;

function toIsoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function computeDateFrom(lastSyncAt: Date | null): string {
  const maxLookback = new Date(Date.now() - TX_LOOKBACK_DAYS * 86_400_000);
  if (!lastSyncAt) return toIsoDate(maxLookback);
  const incremental = new Date(
    lastSyncAt.getTime() - TX_INCREMENTAL_OVERLAP_DAYS * 86_400_000,
  );
  const effective = incremental < maxLookback ? maxLookback : incremental;
  return toIsoDate(effective);
}

export async function syncEnableBankingConnection(
  connectionId: string,
): Promise<SyncResult> {
  const result: SyncResult = {
    connectionId,
    accountsTouched: 0,
    transactionsInserted: 0,
    errors: [],
  };

  await reapStaleSyncRuns();

  const [conn] = await db
    .select()
    .from(connections)
    .where(eq(connections.id, connectionId));
  if (!conn) throw new Error(`Connection ${connectionId} not found`);
  if (conn.connector !== "enablebanking") {
    throw new Error(`Connection ${connectionId} is not an enablebanking connection`);
  }
  if (!conn.sessionId) {
    throw new Error(`Connection ${connectionId} has no session_id`);
  }

  const [run] = await db
    .insert(syncRuns)
    .values({ connector: "enablebanking", connectionId })
    .returning();

  const client = new EnableBankingClient();
  const insertedIds: string[] = [];
  const defaultSpaceId = await getDefaultSpaceId();

  try {
    const session = await client.getSession(conn.sessionId);
    if (session.status !== "AUTHORIZED") {
      const status = session.status === "REVOKED" || session.status === "INVALID" || session.status === "CLOSED"
        ? ("expired" as const)
        : ("error" as const);
      await db
        .update(connections)
        .set({
          status,
          lastError: `Session status: ${session.status}`,
          updatedAt: new Date(),
        })
        .where(eq(connections.id, connectionId));
      await db
        .update(syncRuns)
        .set({
          finishedAt: new Date(),
          status: "error",
          error: `session ${session.status}`,
        })
        .where(eq(syncRuns.id, run.id));
      result.errors.push(`session ${session.status}`);
      return result;
    }

    const sessionAccounts = sessionAccountsOf(session);
    result.accountsTouched = sessionAccounts.length;

    const ebConnectionIds = (
      await db
        .select({ id: connections.id })
        .from(connections)
        .where(eq(connections.connector, "enablebanking"))
    ).map((r) => r.id);

    for (const sessionAccount of sessionAccounts) {
      try {
        if (!isValidUid(sessionAccount.uid)) {
          await db
            .update(connections)
            .set({
              metadata: {
                ...(conn.metadata ?? {}),
                lastBadAccount: sessionAccount as unknown as Record<string, unknown>,
                lastBadAccountAt: new Date().toISOString(),
              },
            })
            .where(eq(connections.id, connectionId));
          result.errors.push(
            `bad-uid: Enable Banking returned an account with an invalid uid (${JSON.stringify(sessionAccount.uid)}). Re-authorize the connection.`,
          );
          continue;
        }
        const details = await client.getAccountDetails(sessionAccount.uid);
        const balancesResp = await client.getAccountBalances(sessionAccount.uid);
        const interim = preferredBalance(balancesResp.balances);
        const iban = ibanOf(details) ?? ibanOf(sessionAccount);

        const normalizeCurrency = (c: string | null | undefined): string | null =>
          c && /^[A-Z]{3}$/.test(c) && c !== "XXX" ? c : null;
        const currency =
          normalizeCurrency(details.currency) ??
          normalizeCurrency(sessionAccount.currency) ??
          normalizeCurrency(interim?.balance_amount.currency) ??
          "EUR";

        const baseAccountValues: NewAccount = {
          connectionId,
          externalId: sessionAccount.uid,
          type: "bank",
          institution: conn.institutionName ?? conn.institutionId ?? "Unknown",
          name:
            details.name ??
            sessionAccount.name ??
            details.product ??
            sessionAccount.product ??
            iban ??
            "Account",
          currency,
          iban,
          balance: interim ? interim.balance_amount.amount : null,
          balanceUpdatedAt: new Date(),
          spaceId: defaultSpaceId,
          metadata: {
            session: sessionAccount as unknown as Record<string, unknown>,
            details: details as unknown as Record<string, unknown>,
          },
        };

        const [existingByExternal] = await db
          .select()
          .from(accounts)
          .where(
            and(
              eq(accounts.connectionId, connectionId),
              eq(accounts.externalId, sessionAccount.uid),
            ),
          );

        const existingByIban = iban && !existingByExternal
          ? await db
              .select()
              .from(accounts)
              .where(
                and(
                  inArray(accounts.connectionId, ebConnectionIds),
                  eq(accounts.iban, iban),
                ),
              )
          : [];

        if (existingByIban.length > 1) {
          result.errors.push(
            `iban-ambiguous: ${iban} matches ${existingByIban.length} accounts across connections; refusing to re-point automatically. Resolve manually before continuing.`,
          );
          continue;
        }

        let resolved = existingByExternal ?? existingByIban[0] ?? null;

        if (
          resolved &&
          (resolved.connectionId !== connectionId ||
            resolved.externalId !== sessionAccount.uid)
        ) {
          const collision =
            resolved.connectionId === connectionId
              ? null
              : (
                  await db
                    .select({ id: accounts.id })
                    .from(accounts)
                    .where(
                      and(
                        eq(accounts.connectionId, connectionId),
                        eq(accounts.externalId, sessionAccount.uid),
                      ),
                    )
                )[0] ?? null;
          if (collision && collision.id !== resolved.id) {
            result.errors.push(
              `merge-conflict: ${iban ?? sessionAccount.uid} already exists on this connection under a different account row; skipping cross-connection merge.`,
            );
            continue;
          }
          const previousConnectionId = resolved.connectionId;
          const repointed = await db
            .update(accounts)
            .set({
              connectionId,
              externalId: sessionAccount.uid,
            })
            .where(eq(accounts.id, resolved.id))
            .returning();
          resolved = repointed[0] ?? resolved;
          if (previousConnectionId && previousConnectionId !== connectionId) {
            const [oldConn] = await db
              .select()
              .from(connections)
              .where(eq(connections.id, previousConnectionId));
            if (oldConn) {
              await db
                .update(connections)
                .set({
                  status: "revoked",
                  metadata: {
                    ...((oldConn.metadata as Record<string, unknown> | null) ?? {}),
                    replacedBy: connectionId,
                    replacedAt: new Date().toISOString(),
                  },
                  updatedAt: new Date(),
                })
                .where(eq(connections.id, previousConnectionId));
            }
          }
        }

        if (resolved?.archived) {
          await db
            .update(accounts)
            .set({
              metadata: {
                ...((resolved.metadata as Record<string, unknown> | null) ?? {}),
                lastDiscoveredAt: new Date().toISOString(),
              },
            })
            .where(eq(accounts.id, resolved.id));
          continue;
        }

        let accountId: string;
        let fullSyncForThisAccount = false;
        if (!resolved) {
          await db
            .insert(accounts)
            .values({
              ...baseAccountValues,
              archived: true,
              balance: null,
              balanceUpdatedAt: null,
              metadata: {
                ...(baseAccountValues.metadata ?? {}),
                discoveredAt: new Date().toISOString(),
                pendingApproval: true,
              },
            })
            .onConflictDoNothing({
              target: [accounts.connectionId, accounts.externalId],
            });
          continue;
        } else {
          const prevMeta =
            (resolved.metadata as Record<string, unknown> | null) ?? {};
          fullSyncForThisAccount = prevMeta.fullSyncRequested === true;
          const currencyOverridden = prevMeta.currencyOverride === true;
          const mergedMetadata: Record<string, unknown> = {
            ...prevMeta,
            ...(baseAccountValues.metadata ?? {}),
          };
          if (fullSyncForThisAccount) delete mergedMetadata.fullSyncRequested;
          if (currencyOverridden) mergedMetadata.currencyOverride = true;
          const updated = await db
            .update(accounts)
            .set({
              name: baseAccountValues.name,
              currency: currencyOverridden
                ? resolved.currency
                : baseAccountValues.currency,
              iban: baseAccountValues.iban,
              balance: baseAccountValues.balance,
              balanceUpdatedAt: baseAccountValues.balanceUpdatedAt,
              metadata: mergedMetadata,
            })
            .where(eq(accounts.id, resolved.id))
            .returning();
          accountId = updated[0].id;
        }

        const dateFrom = fullSyncForThisAccount
          ? toIsoDate(new Date(Date.now() - TX_LOOKBACK_DAYS * 86_400_000))
          : computeDateFrom(conn.lastSyncAt);
        let continuationKey: string | undefined;
        let pages = 0;
        do {
          const resp = await client.getAccountTransactions(sessionAccount.uid, {
            transactionStatus: "BOOK",
            dateFrom,
            strategy: "longest",
            continuationKey,
          });
          for (let txIndex = 0; txIndex < resp.transactions.length; txIndex++) {
            const t = resp.transactions[txIndex];
            if (Number(t.transaction_amount.amount) === 0) continue;
            const fallbackId = `${sessionAccount.uid}:${t.booking_date ?? t.value_date ?? ""}:${t.transaction_amount.amount}:${t.credit_debit_indicator}:${t.entry_reference ?? `p${pages}-i${txIndex}`}`;
            const externalId = pickExternalId(t, fallbackId);
            const txValues: NewTransaction = {
              accountId,
              externalId,
              bookedAt: pickBookingDate(t),
              valueAt: pickValueDate(t),
              amount: signedAmount(t),
              currency: t.transaction_amount.currency,
              direction: t.credit_debit_indicator === "CRDT" ? "credit" : "debit",
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
            for (const row of inserted) insertedIds.push(row.id);
            result.transactionsInserted += inserted.length;
          }
          continuationKey = resp.continuation_key;
          pages++;
        } while (continuationKey && pages < TX_PAGE_LIMIT);
      } catch (err) {
        const detail =
          err instanceof EnableBankingError
            ? `${err.status} ${typeof err.body === "string" ? err.body : JSON.stringify(err.body)}`
            : err instanceof Error
              ? err.message
              : String(err);
        const label =
          sessionAccount.uid ??
          ibanOf(sessionAccount) ??
          sessionAccount.identification_hash ??
          "account";
        result.errors.push(`${label}: ${detail}`);
      }
    }

    const expiresAt = session.access?.valid_until ? new Date(session.access.valid_until) : null;

    let fxBackfilled = 0;
    let fxSkipped = 0;
    let categorized = 0;
    let routedMirrors = 0;
    let transfersMatched = 0;

    if (insertedIds.length > 0) {
      try {
        const fx = await backfillTransactionEurAmounts({ sinceDays: 90 });
        fxBackfilled = fx.updated;
        fxSkipped = fx.skipped;
      } catch (err) {
        result.errors.push(`fx: ${err instanceof Error ? err.message : String(err)}`);
      }
      try {
        const cats = await applyRulesToTransactions(insertedIds);
        categorized = cats.updated;
      } catch (err) {
        result.errors.push(`categorize: ${err instanceof Error ? err.message : String(err)}`);
      }
      try {
        const routed = await applyTransferRoutes({ txIds: insertedIds });
        routedMirrors = routed.mirroredCreated;
      } catch (err) {
        result.errors.push(`routes: ${err instanceof Error ? err.message : String(err)}`);
      }
      try {
        const transfers = await detectTransfers({ sinceDays: 30 });
        transfersMatched = transfers.matched;
      } catch (err) {
        result.errors.push(`transfers: ${err instanceof Error ? err.message : String(err)}`);
      }
    }
    try {
      await repairTransferGroups();
    } catch (err) {
      result.errors.push(`repair: ${err instanceof Error ? err.message : String(err)}`);
    }
    try {
      const violations = await assertTransferInvariants();
      if (violations.length > 0) {
        result.errors.push(`invariants: ${formatInvariantViolations(violations)}`);
      }
    } catch (err) {
      result.errors.push(
        `invariants-check: ${err instanceof Error ? err.message : String(err)}`,
      );
    }
    result.postProcess = { fxBackfilled, fxSkipped, categorized, routedMirrors, transfersMatched };

    await db
      .update(connections)
      .set({
        status: result.errors.length > 0 ? "error" : "active",
        lastSyncAt: new Date(),
        lastError: result.errors.length > 0 ? result.errors.join("; ") : null,
        expiresAt: expiresAt ?? undefined,
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
    const expired = err instanceof EnableBankingError && (err.status === 401 || err.status === 403);
    await db
      .update(connections)
      .set({
        status: expired ? "expired" : "error",
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

export async function syncAllEnableBankingConnections(): Promise<SyncResult[]> {
  const rows = await db
    .select()
    .from(connections)
    .where(eq(connections.connector, "enablebanking"));
  const out: SyncResult[] = [];
  for (const row of rows) {
    if (row.status === "revoked" || row.status === "expired") continue;
    try {
      out.push(await syncEnableBankingConnection(row.id));
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

export type { EbTransaction };
