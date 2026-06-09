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
  ImportFromPostgres/   One-shot SwiftPM executable. Reads JSON dump → writes local SwiftData .store file.
  ExportFromPostgres/   Node .mjs script. Reads Neon Postgres → emits the JSON dump.
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
- **Never call `ctx.delete(model)` directly on `Account`, `Transaction`, `SharedExpenseGroup`, or `Connection`.** SwiftData's `@Relationship(deleteRule: .cascade)` is unreliable — verified in tests. Go through `CoreLogic.delete*(_:in:)` helpers; they fetch related objects by predicate and delete explicitly. The `@Relationship` cascade declarations on the model file are documented intent only.
- **Recursive cascades** (`Transaction.routedFromTx`, `Category.parent`) are real and intentional. Don't downgrade to `.nullify` without reason — the cascade helper is what actually enforces them.
- **Composite uniqueness** (e.g. `Transaction(account.id, externalId)`) is enforced in code, not by SwiftData. Insert paths must check first or rely on `CKRecord.ID` name encoding.
- **jsonb columns** become `Data?` Codable blobs. Anything load-bearing (like `routeId`) gets denormalized to a first-class column.
- **All Core code is platform-agnostic** (iOS + macOS) so tests run on the Mac without booting a simulator.

## What's done vs pending

- ✅ Step 0 — scaffold (xcodegen, Core package, 14 `@Model` types, App skeleton)
- ✅ Step 1 — port `lib/fx.ts` to `CoreLogic/FX` (ECB XML parser + EUR conversion). 10 tests passing.
- ✅ Step 1.5 — explicit cascade helpers in `CoreLogic/Cascades.swift`. 4 tests passing.
- ✅ Step 2 — port `lib/categorize.ts` + `lib/rules.ts` to `CoreLogic/Categorize`. 17 tests passing.
- ✅ Step 3 — port `lib/transfers.ts` + `lib/transfer-routes.ts` + `lib/transfer-invariants.ts` + `lib/account-status.ts`. 39 tests passing.
- ✅ Step 4 — port `lib/shared-expenses.ts` to `CoreLogic/SharedExpenses`. 24 tests passing.
- ✅ Step 5 — port `lib/investments.ts` to `CoreLogic/Investments`. 17 tests passing.
- ✅ Step 6 — `Tools/ImportFromPostgres` (Swift CLI) + `Tools/ExportFromPostgres` (Node script). JSON-dump contract via `DumpDocument`. Backfills: `categorySource` NULL→`.bank` with `_legacyCategorySourceNull` marker in `rawJSON`; `attributionMonth` falls back to `primaryTx.bookedAt` month-start. TransferGroups synthesized by exporter (`pairedAt = MIN(bookedAt)`, `routeId = MAX(raw->>'routeId')`). 15 importer tests passing.
- ✅ Step 7a — `CoreSync` pure core: `Sendable` `*Snapshot` structs for all 14 models, `CKRecord` ↔ Snapshot round-trip encoding (Decimals as strings, UUIDs as strings, enums as rawValue, relations as referenced-UUID strings — no `CKReference`), LWW conflict resolver with `categorySource == .manual` override for `Transaction`, composite-uniqueness dedupe for `Transaction(accountId, externalId)` (S5) and `FxRate(date, currency)` (N6). 38 CoreSync tests.
- 🟨 Step 7b — CoreSync integration: `@MainActor` `Model ↔ Snapshot` adapters; `PullPipeline.apply` (dependency-ordered, 2-pass for the Tx↔SEG cycle, dedupe via 7a); `PushPipeline.{pendingChanges, nextBatch, buildRecord}`; `SyncStateStore` (Application Support file); `CloudKitSyncEngine` conforming to `CKSyncEngineDelegate` (handles stateUpdate, fetchedRecordZoneChanges, fetchedDatabaseChanges, zone re-enqueue); `BackgroundSync.{register, schedule}` (iOS-gated `BGProcessingTask` wired to `engine.fetchOnLaunch + sendPendingChanges + reschedule`). App.swift instantiates the engine, registers BG handler in init, calls `engine.start() + fetchOnLaunch()` after auth. **30 new tests** cover ModelSnapshots adapters, PullPipeline (insert/update/LWW/manual-override/dedupe/cycle-relink/delete/unknown-type/decode-failure), PushPipeline (build/translate/prebuild/cross-context round-trip), SyncStateStore. **On-device verification still required**: actual CloudKit round-trip, schema bootstrap in CloudKit dashboard, BGTaskScheduler firing, state durability across launches. 183 tests green total.
- ⏳ Step 8 — Vercel proxy for Enable Banking
- ⏳ Step 9 — SwiftUI views
