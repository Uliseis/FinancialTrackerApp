# FinancialTracker

Single-user EU/Spain personal finance dashboard. Self-hosted on Vercel Hobby (free tier). Consolidates banks, brokers, and crypto into one view with cash flow, allocation, and PNL.

Bank connectivity uses **Enable Banking** (PSD2 AIS, JWT-signed REST API). The previous GoCardless integration was removed; no compatibility code remains.

## Stack (installed, latest at scaffold time)

- **Next.js 16** (App Router, Turbopack), **React 19**, **TypeScript 6**, `"type": "module"`
- **Tailwind CSS v4** — CSS-first config in `app/globals.css` via `@import "tailwindcss"` + `@theme inline`. PostCSS plugin: `@tailwindcss/postcss`. **No `tailwind.config.ts`** — do not add one.
- **shadcn-style primitives written by hand** in `components/ui/` (Button, Card, Badge, Table, NativeSelect). Not installed via the shadcn CLI.
- **NextAuth v5 beta** — GitHub OAuth, single-email allowlist via `signIn` callback (`lib/auth.ts`). JWT sessions.
- **Drizzle ORM 0.45** + **Neon serverless Postgres** (`@neondatabase/serverless` + `drizzle-orm/neon-http`).
- **Vercel Cron** (daily) defined in `vercel.json`.

## Next 16 conventions to remember

- The middleware file is **`proxy.ts` at the project root**, not `middleware.ts`. Default export wraps `auth(...)` from NextAuth.
- Server-component `searchParams` and `params` are **`Promise`s** — `await` them.

## File map

```
app/
  layout.tsx, page.tsx, globals.css, login/page.tsx
  connect/{page.tsx, connect-form.tsx}
  connections/{page.tsx, row-actions.tsx}
  transactions/page.tsx
  api/auth/[...nextauth]/route.ts
  api/enablebanking/{aspsps,connect,callback,sync}/route.ts
components/ui/          Button, Card, Badge, Table, NativeSelect
db/schema.ts            Drizzle schema (9 tables, enums)
db/migrate.ts           tsx-runnable migrator
drizzle/                Generated SQL + meta (committed)
lib/
  auth.ts               NextAuth + email allowlist
  db.ts                 Drizzle client (Neon HTTP)
  env.ts                Lazy `required()` getters — throw on missing
  crypto.ts             AES-256-GCM helpers (encrypt/decrypt)
  enablebanking.ts      Typed client (RS256 JWT signer, aspsps, auth, sessions, accounts, balances, tx)
  sync-enablebanking.ts Per-connection sync: validate session, upsert accounts (iban fallback), paginated booked tx, dedupe on (account_id, external_id)
  utils.ts              cn(), formatCurrency(), formatDate()
proxy.ts                Auth proxy — public-paths allowlist, 401 JSON for /api, 307 for pages
vercel.json             Cron: GET /api/enablebanking/sync at 06:00 UTC daily
```

## Commands

```
npm run dev           # next dev (Turbopack)
npm run build         # next build
npm run typecheck     # tsc --noEmit
npm run db:generate   # drizzle-kit generate (after schema edits)
npm run db:migrate    # tsx db/migrate.ts (apply migrations to DATABASE_URL)
npm run db:push       # drizzle-kit push (dev shortcut, skip migrations)
npm run db:studio     # drizzle-kit studio (DB GUI)
```

## Env vars (see `.env.example`)

| Var | Source |
|---|---|
| `DATABASE_URL` | Neon pooled connection string |
| `NEXTAUTH_SECRET` | `openssl rand -base64 32` |
| `NEXTAUTH_URL` | Site URL (`http://localhost:3000` in dev, Vercel URL in prod) |
| `GITHUB_ID` / `GITHUB_SECRET` | https://github.com/settings/developers |
| `ALLOWED_EMAIL` | The single email allowed to sign in |
| `ENCRYPTION_KEY` | `openssl rand -base64 32` — must decode to 32 bytes |
| `ENABLEBANKING_APPLICATION_ID` | UUID from https://enablebanking.com/cp/ — used as JWT `kid` |
| `ENABLEBANKING_PRIVATE_KEY` | RSA private key (PEM or single-line base64) registered for the application |
| `ENABLEBANKING_REDIRECT_URL` (optional) | Defaults to `${NEXTAUTH_URL}/api/enablebanking/callback` |
| `CRON_SECRET` (optional) | Bearer for manual `/api/enablebanking/sync` calls |

## Auth model

- Only `ALLOWED_EMAIL` (case-insensitive) can sign in. Any other GitHub email gets rejected by the `signIn` callback.
- `proxy.ts` allowlists `/login`, `/api/auth/*`, and `/api/enablebanking/sync` (cron-authenticated). Everything else: pages 307 → `/login`, `/api/*` returns `401 {"error":"unauthorized"}`.
- The cron route also accepts `Authorization: Bearer ${CRON_SECRET}` (Vercel Cron sends this when configured).

## Enable Banking flow

1. `POST /api/enablebanking/connect` with `{aspspName, aspspCountry, psuType}` → calls `POST /auth` with a `valid_until` timestamp (90 days), inserts a `connections` row (`status=pending`, state stored in `metadata`), returns `{link}`.
2. Client redirects user to `link`. User authorizes at the bank.
3. Bank redirects to `GET /api/enablebanking/callback?code=<code>&state=<state>` → matches the connection by `metadata->>'state'`, exchanges the code via `POST /sessions`, persists `session_id` + `valid_until` (as `expiresAt`), kicks off initial sync, redirects to `/connections?connected=1`.
4. `syncEnableBankingConnection(connectionId)`: validates via `GET /sessions/{id}`, upserts `accounts` per session-account uid (with IBAN fallback when the bank rotates uids on re-auth), paginates booked transactions via `transaction_status=BOOK` + `continuation_key`, upserts transactions on `(account_id, external_id)` with `onConflictDoNothing`. `credit_debit_indicator` (CRDT/DBIT) is mapped to `tx_direction` and the stored `amount` is signed accordingly. Errors are persisted on `connections.last_error` and on a `sync_runs` row.

JWT auth: every request signs an RS256 JWT in-process (`kid=ENABLEBANKING_APPLICATION_ID`, `iss=enablebanking.com`, `aud=api.enablebanking.com`, 1 h TTL) with the registered RSA private key. No token cache.

## Conventions

- **Encrypt at rest** any access tokens / refresh tokens with `lib/crypto.ts` (`access_token_enc`, `refresh_token_enc` columns are `text`). The current Enable Banking flow stores only the `session_id` (not itself a credential), so encryption fields are unused so far — use them for Trading212 / Revolut X.
- **Numerics** are stored as `numeric` and serialized to `string` by Drizzle — `parseFloat` at the UI edge.
- **Use `lib/env.ts` getters** rather than reading `process.env` directly outside it, so missing values throw a clear error.
- **All page server components that hit the DB** declare `export const dynamic = "force-dynamic"`.
- **No comments unless the why is non-obvious.** No README. No multi-paragraph docstrings.

## What's done vs pending

- ✅ Step 1 — scaffold, auth, DB schema, migrations, encryption helper
- ✅ Step 2 — Enable Banking integration (JWT auth, /auth → /sessions flow, paginated tx sync, re-auth UI)
- ⏳ Step 3 — dashboard v1 (net worth, monthly cash flow, category breakdown)
- ⏳ Step 4 — Trading212 (REST API → holdings + transactions)
- ⏳ Step 5 — Revolut X crypto (holdings + trades)
- ⏳ Step 6 — investment dashboard (allocation pie, realized/unrealized PNL, TWR; Yahoo/stooq + CoinGecko prices)
- ⏳ Step 7 — categorization rules engine (`category_rules` table already exists)
- ⏳ Step 8 — daily Vercel Cron wired to all syncs (enablebanking route + cron schedule already wired; add others)

## Gotchas

- **Tailwind 4** — no `bg-background hsl(var(--...))` pattern; use `bg-[var(--color-background)]` (or define utilities in `@theme`). The `--color-*` tokens in `globals.css` are what Tailwind 4 reads.
- **`@neondatabase/serverless`** uses HTTP fetch, so `lib/db.ts` is import-safe in edge / serverless contexts. Don't switch to `pg` driver without reason.
- **Migrations are committed** under `drizzle/`. After every `db/schema.ts` edit, run `npm run db:generate`, review the SQL, commit.
- **Multiple lockfiles** — `next.config.ts` sets `turbopack.root` to silence the workspace-root warning if a stray `package-lock.json` exists in a parent directory.
