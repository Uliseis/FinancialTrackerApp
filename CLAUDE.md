# FinancialTracker (iOS)

Native SwiftUI rewrite of the Next.js web app. Single-user EU/Spain personal finance app. iCloud-only storage (no server DB). The web app at `Spec/` is the **port spec** — read it, don't edit it.

## Stack

- **SwiftUI + Swift Charts**, iOS 18+ minimum.
- **SwiftData** `@Model` types as the local store.
- **CloudKit private DB via `CKSyncEngine`** (hand-rolled sync layer, not `NSPersistentCloudKitContainer`).
- **Face ID** on app open via `LocalAuthentication`. No account system — the iCloud account is the boundary.
- **xcodegen** for the `.xcodeproj`. Spec lives at `project.yml`.
- **`Core` Swift Package** (in `Core/`) holds all ported business logic. The `App` target is SwiftUI-only.

## Hard rules

- **No comments unless the why is non-obvious.** No multi-paragraph docstrings.
- **Do not edit anything under `Spec/`.** It's a frozen reference snapshot of the live Next.js app. The live app continues to run on Vercel until iOS parity is reached.
- **EUR primary currency, ECB FX rates.** Same as the web app.
- **Numerics are `Decimal`**, never `Double`. Match Postgres `numeric(p,s)` precision.
- **Single user — me.** Don't build multi-tenant abstractions.

## Locked decisions (do not re-litigate)

| Topic | Decision |
|---|---|
| Data cutover | One-shot import from Neon Postgres. UUIDs + transfer-group + mirror chains preserved. |
| Spaces | Keep general (N spaces). Cross-space invariants stay load-bearing. |
| Shared expenses | Kept. |
| Investment data | `portfolio_valuations` snapshots only. `Instrument` / `Holding` / `Price` NOT ported. |
| `category_source` | Non-optional `CategorySource` enum. Nulls backfilled to `.bank` at import. |
| Sync conflict policy | Last-writer-wins, except `categorySource == .manual` always beats a non-manual write. |
| Vercel function | Returns pre-normalized rows. Lives at `Vercel/` inside this dir. |
| CloudKit container | `iCloud.com.uliseis.financialtracker` |

## File map

```
App/                    SwiftUI target. @main, Face ID gate, ModelContainer wiring.
  App.swift
  FinancialTracker.entitlements
  Features/             per-feature folders (Accounts, Transactions, Transfers, …)
Core/                   Swift package. Pure-Swift business logic + models.
  Package.swift
  Sources/
    CoreModel/          @Model types + enums. No logic.
    CoreLogic/          Ported lib/* logic. Tests live alongside.
    CoreIntegrations/   HTTP clients (Enable Banking via proxy, Trading212, Revolut X). Keychain. Named to avoid collision with Apple's CoreServices framework.
    CoreSync/           CKSyncEngine, BGProcessingTask, conflict resolver.
  Tests/
Tools/
  ImportFromPostgres/   One-shot SwiftPM executable. Reads JSON dump → writes CloudKit.
Vercel/                 Thin TS proxy for Enable Banking. RS256 JWT signing.
Spec/                   ← READ-ONLY. Frozen Next.js app + lib/*.ts spec. Live web app builds from here.
project.yml             xcodegen spec.
```

## Commands

```
xcodegen generate     # regenerate the .xcodeproj from project.yml
open *.xcodeproj      # work in Xcode
swift test --package-path Core   # run Core package tests from CLI
```

## Conventions

- **Inverse relationships explicit.** SwiftData wants the `@Relationship(inverse:)` declared on one side; pick the parent and own it there.
- **Recursive cascades** (`Transaction.routedFromTx`, `Category.parent`) are real and intentional. Don't downgrade to `.nullify` without reason.
- **Composite uniqueness** (e.g. `Transaction(account.id, externalId)`) is enforced in code, not by SwiftData. Insert paths must check first or rely on `CKRecord.ID` name encoding.
- **jsonb columns** become `Data?` Codable blobs. Anything load-bearing (like `routeId`) gets denormalized to a first-class column.
- **All Core code is platform-agnostic** (iOS + macOS) so tests run on the Mac without booting a simulator.

## What's done vs pending

- ✅ Step 0 — scaffold (xcodegen, Core package, 14 `@Model` types, App skeleton)
- ⏳ Step 1 — port `lib/fx.ts` to `CoreLogic/FX` (ECB XML parser + EUR conversion). First green test.
- ⏳ Step 2 — port `lib/categorize.ts` + `lib/rules.ts`
- ⏳ Step 3 — port `lib/transfers.ts` + `lib/transfer-routes.ts` + `lib/transfer-invariants.ts` (5 invariants → 5 tests)
- ⏳ Step 4 — port `lib/shared-expenses.ts`
- ⏳ Step 5 — port `lib/investments.ts` (baseline, cost basis, series)
- ⏳ Step 6 — Tools/ImportFromPostgres
- ⏳ Step 7 — CoreSync (CKSyncEngine + LWW-except-manual resolver + BGProcessingTask)
- ⏳ Step 8 — Vercel proxy for Enable Banking
- ⏳ Step 9 — SwiftUI views
