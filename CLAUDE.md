# FinancialTracker (iOS)

Native SwiftUI rewrite of the Next.js web app. Single-user EU/Spain personal finance app. iCloud-only storage (no server DB). The web app at `Spec/` is the **port spec** — read it, don't edit it.

## Stack

- **SwiftUI + Swift Charts**, iOS 26+ minimum (iPhone 17 family — iPhone 17 Pro Max for dev). macOS 26+ for Core package + Tools (so `swift test` runs on the dev Mac).
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
| Enable Banking | **On-device, no server (changed 2026-06-09, was a Vercel proxy).** RS256 JWT signed on-device (Security framework); RSA app key in the Keychain, biometric-gated + iCloud-synced (`kSecAttrSynchronizable`). REST called directly from `CoreIntegrations`. Single-user app ⇒ the key never ships in a distributed binary, so the original "key in binary" risk doesn't apply. |
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
    CoreIntegrations/   HTTP clients (Enable Banking direct, Trading212, Revolut X). On-device RS256 JWT signing + Keychain. Named to avoid collision with Apple's CoreServices framework.
    CoreSync/           CKSyncEngine, BGProcessingTask, conflict resolver.
  Tests/
Tools/
  ImportFromPostgres/   One-shot SwiftPM executable. Reads JSON dump → writes local SwiftData .store file.
  ExportFromPostgres/   Node .mjs script. Reads Neon Postgres → emits the JSON dump.
Vercel/                 (unused — Enable Banking moved on-device 2026-06-09; may host a static apple-app-site-association for the auth redirect Universal Link).
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
- **Bare `ctx.delete(model)` is fine.** SwiftData's `@Relationship(deleteRule: .cascade / .nullify)` fires reliably on iOS 26 (the iOS 18 bug behind the old `Cascades.swift` helpers no longer reproduces — re-verified 2026-06-09). `CascadeTests.swift` is the regression guard for all four delete shapes (cascade + nullify); if it ever fails on a future SDK, restore explicit helpers.
- **Recursive cascades** (`Transaction.routedFromTx`, `Category.parent`) are real and intentional. Don't downgrade to `.nullify` without reason — the `@Relationship(deleteRule: .cascade)` declaration is what enforces them.
- **Composite uniqueness** (e.g. `Transaction(account.id, externalId)`, `FxRate(date, currency)`) is enforced in `CoreSync` (`CompositeDedupe` + the PullPipeline dedupe branches), NOT by SwiftData's `#Unique` macro. `#Unique` exists on iOS 26 but resolves conflicts by silent non-deterministic upsert that overwrites the row's `id` — incompatible with the `CKRecord.recordName == id` sync invariant and cross-device-deterministic winner selection. Keep dedupe in code.
- **jsonb columns** become `Data?` Codable blobs. Anything load-bearing (like `routeId`) gets denormalized to a first-class column.
- **All Core code is platform-agnostic** (iOS + macOS) so tests run on the Mac without booting a simulator.

## What's done vs pending

- ✅ Step 0 — scaffold (xcodegen, Core package, 14 `@Model` types, App skeleton)
- ✅ Step 1 — port `lib/fx.ts` to `CoreLogic/FX` (ECB XML parser + EUR conversion). 10 tests passing.
- ✅ Step 1.5 — ~~explicit cascade helpers in `CoreLogic/Cascades.swift`~~ **retired 2026-06-09**: iOS 26 cascades are reliable, deletes go through bare `ctx.delete`. `CascadeTests.swift` (8 tests) is the regression guard.
- ✅ Step 2 — port `lib/categorize.ts` + `lib/rules.ts` to `CoreLogic/Categorize`. 17 tests passing.
- ✅ Step 3 — port `lib/transfers.ts` + `lib/transfer-routes.ts` + `lib/transfer-invariants.ts` + `lib/account-status.ts`. 39 tests passing.
- ✅ Step 4 — port `lib/shared-expenses.ts` to `CoreLogic/SharedExpenses`. 24 tests passing.
- ✅ Step 5 — port `lib/investments.ts` to `CoreLogic/Investments`. 17 tests passing.
- ✅ Step 6 — `Tools/ImportFromPostgres` (Swift CLI) + `Tools/ExportFromPostgres` (Node script). JSON-dump contract via `DumpDocument`. Backfills: `categorySource` NULL→`.bank` with `_legacyCategorySourceNull` marker in `rawJSON`; `attributionMonth` falls back to `primaryTx.bookedAt` month-start. TransferGroups synthesized by exporter (`pairedAt = MIN(bookedAt)`, `routeId = MAX(raw->>'routeId')`). 15 importer tests passing.
- ✅ Step 7a — `CoreSync` pure core: `Sendable` `*Snapshot` structs for all 14 models, `CKRecord` ↔ Snapshot round-trip encoding (Decimals as strings, UUIDs as strings, enums as rawValue, relations as referenced-UUID strings — no `CKReference`), LWW conflict resolver with `categorySource == .manual` override for `Transaction`, composite-uniqueness dedupe for `Transaction(accountId, externalId)` (S5) and `FxRate(date, currency)` (N6). 38 CoreSync tests.
- 🟨 Step 7b — CoreSync integration: `@MainActor` `Model ↔ Snapshot` adapters; `PullPipeline.apply` (dependency-ordered, 2-pass for the Tx↔SEG cycle, dedupe via 7a); `PushPipeline.{pendingChanges, nextBatch, buildRecord}`; `SyncStateStore` (Application Support file); `CloudKitSyncEngine` conforming to `CKSyncEngineDelegate` (handles stateUpdate, fetchedRecordZoneChanges, fetchedDatabaseChanges, zone re-enqueue); `BackgroundSync.{register, schedule}` (iOS-gated `BGProcessingTask` wired to `engine.fetchOnLaunch + sendPendingChanges + reschedule`). App.swift instantiates the engine, registers BG handler in init, calls `engine.start() + fetchOnLaunch()` after auth. **30 new tests** cover ModelSnapshots adapters, PullPipeline (insert/update/LWW/manual-override/dedupe/cycle-relink/delete/unknown-type/decode-failure), PushPipeline (build/translate/prebuild/cross-context round-trip), SyncStateStore. **On-device verification still required**: actual CloudKit round-trip, schema bootstrap in CloudKit dashboard, BGTaskScheduler firing, state durability across launches. 183 tests green total.
- ✅ iOS 26 audit (2026-06-09) — toolchain on macOS 26.5 / Xcode 26.5. Retired `Cascades.swift` (1a); removed Swift 6 `.v5` language-mode dodges from `Core/Package.swift` — whole package builds clean at `.v6` (1e); wired a single `SaveObserver` (`ModelContext.didSave`/`willSave`) into `CloudKitSyncEngine.start()` so UI saves auto-push, no per-view `enqueueLocalChanges` needed (1c). Deferred: `#Unique` for sync dedupe (1b, non-deterministic upsert). No CloudKit schema-as-code API exists (1d) — dashboard/JIT bootstrap stays. **191 Core + 15 importer tests green.**
- ⏳ Step 8 — Enable Banking **on-device** in `CoreIntegrations` (was Vercel proxy; re-decided 2026-06-09): RS256 JWT signer (Security framework), Keychain key store (biometric + iCloud-synced), direct REST client (aspsps/auth/sessions/accounts), Codable models + Decimal helpers. Auth redirect via `ASWebAuthenticationSession` + Universal Link (Step 9.7). Tests cover signer + decoders + helpers (no live calls).
- ⏳ Step 9 — SwiftUI views: adopt iOS 26 Liquid Glass baseline (`glassEffect`/`GlassEffectContainer`, `.buttonStyle(.glassProminent)`, `ToolbarSpacer`, `tabBarMinimizeBehavior`, `scrollEdgeEffectStyle`). Save paths push automatically via `SaveObserver` (observe the main context only — never the engine's sync context).
