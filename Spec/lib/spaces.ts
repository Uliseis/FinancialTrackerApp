import { asc, eq, or, isNull, sql, type SQL } from "drizzle-orm";
import { db } from "@/lib/db";
import { accountSpaces, accounts, type AccountSpace } from "@/db/schema";

export async function getDefaultSpaceId(): Promise<string> {
  const [row] = await db
    .select({ id: accountSpaces.id })
    .from(accountSpaces)
    .where(eq(accountSpaces.isDefault, true))
    .limit(1);
  if (row) return row.id;
  const [created] = await db
    .insert(accountSpaces)
    .values({ name: "Individual", color: "#3b82f6", isDefault: true, sortOrder: 0 })
    .returning({ id: accountSpaces.id });
  return created.id;
}

export async function listSpaces(): Promise<AccountSpace[]> {
  return db
    .select()
    .from(accountSpaces)
    .orderBy(asc(accountSpaces.sortOrder), asc(accountSpaces.createdAt));
}

export async function resolveSpaceId(
  raw: string | string[] | undefined,
): Promise<string> {
  const defaultId = await getDefaultSpaceId();
  const v = Array.isArray(raw) ? raw[0] : raw;
  if (!v) return defaultId;
  const [row] = await db
    .select({ id: accountSpaces.id })
    .from(accountSpaces)
    .where(eq(accountSpaces.id, v))
    .limit(1);
  return row?.id ?? defaultId;
}

export function accountInSpaceClause(spaceId: string, defaultId: string): SQL {
  if (spaceId === defaultId) {
    return or(eq(accounts.spaceId, spaceId), isNull(accounts.spaceId))!;
  }
  return eq(accounts.spaceId, spaceId);
}

export async function listAccountIdsInSpace(spaceId: string): Promise<string[]> {
  const defaultId = await getDefaultSpaceId();
  const rows = await db
    .select({ id: accounts.id })
    .from(accounts)
    .where(
      sql`${accountInSpaceClause(spaceId, defaultId)}
          and ${accounts.archived} = false
          and ${accounts.excluded} = false`,
    );
  return rows.map((r) => r.id);
}
