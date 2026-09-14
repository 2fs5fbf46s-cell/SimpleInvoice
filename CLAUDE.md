# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**SmallBiz Workspace** — a SwiftUI + SwiftData iPhone/iPad app for small businesses: clients, jobs, invoices, estimates, contracts (with e-signature), bookings, a file/document workspace, and a hosted client portal.

Names differ at every level and none of them can be "cleaned up" casually:

| Thing | Name |
|---|---|
| Repo directory / GitHub repo | `SimpleInvoice` (legacy — the app was renamed) |
| Xcode project | `SmallBizWorkspace.xcodeproj` |
| App target & source folder | `SmallBiz Workspace` (with a space) |
| Product / module / test `@testable import` | `SmallBizWorkspace` |
| Bundle ID | `com.javonfreeman.smallbizworkspace-` (trailing hyphen is real) |

The server half lives in a **separate repo**: `../smallbizworkspace-portal-backend` (Next.js on Vercel), deployed at `https://portal.smallbizworkspace.com`. Changes to portal payloads usually need matching edits there.

## Build & test

The scheme to use is **`SmallBiz Workspace`** (with the space). The other shared scheme, `SmallBizWorkspace.xcscheme`, is stale — it points at a `SimpleInvoice` target that no longer exists and will fail.

```bash
xcodebuild -project SmallBizWorkspace.xcodeproj -scheme "SmallBiz Workspace" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

```bash
xcodebuild test -project SmallBizWorkspace.xcodeproj -scheme "SmallBiz Workspace" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Single test class or method:

```bash
xcodebuild test -project SmallBizWorkspace.xcodeproj -scheme "SmallBiz Workspace" \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:SmallBizWorkspaceTests/RoutingAcceptanceTests/testInvoicePDFRoutesToJobInvoices
```

- App target deploys to **iOS 17.6+**, but the **test target requires iOS 26.2+** — pick a simulator runtime that satisfies the test target or `xcodebuild test` fails to launch.
- Tests are XCTest (not Swift Testing), `@testable import SmallBizWorkspace`, and build their own in-memory `ModelContainer`.
- Only SPM dependency is ZIPFoundation 0.9.20 (used by the attachment/folder zip exporters).
- The 67 committed `.tmp_*.log` files at the repo root are raw `xcodebuild` transcripts from past sessions, not fixtures. Don't parse them as documentation; don't add more.

## Architecture

### Launch is a staged, gated sequence — not a plain `.modelContainer()`

`SmallBiz WorkspaceApp.swift` shows `AppStartupShellView` until `LaunchCoordinator` reports `.ready`, and only then mounts `RootView` with the container. `LaunchCoordinator.run()` walks fixed phases: `paintingInitialScreen` (deliberately sleeps 120 ms so SwiftUI commits a light shell before any store work) → `preparingStorage` (`AppModelContainerFactory.makeContainer()`) → `runningMigrations` (`BusinessMigration.runIfNeeded`) → `restoringBusiness` → `ready`. Deep links arriving before readiness are queued via `queueIncomingURL` and replayed. Anything you add at startup belongs in a phase here, not in a view's `.task`.

Then `RootView` → `RootGateView` → `OnboardingFlowView` if there are no businesses or onboarding is incomplete, else `AppTabView`.

### SwiftData schema lives in one place

`AppModelContainerFactory.makeContainer()` (bottom of `LaunchCoordinator.swift`) holds the authoritative `Schema([...])`. There are ~30 `@Model` types but not all are registered — a new `@Model` is invisible to the app until added to that list, and the test containers in `SmallBizWorkspaceTests` keep their own parallel lists that also need updating.

`BusinessMigration.currentVersion` (currently 14) is a `UserDefaults`-gated migration counter. Adding a data migration means bumping it.

### Everything is scoped to a business

Multi-business is pervasive. `ActiveBusinessStore` (`@EnvironmentObject`, backed by `@AppStorage("activeBusinessID")`) holds the selected `UUID`. Models carry a plain `businessID: UUID` — **not** a SwiftData relationship to `Business` — and `BusinessScoped.swift` supplies the `BusinessOwned` protocol plus `Array.scoped(to:)`. Use `BusinessScoped.effectiveBusinessID(explicit:activeBusinessID:)` when a view may be handed an explicit business.

Do not add `@Query private var businesses: [Business]` to a detail view just to resolve a business — that pattern caused repeated UI freezes (see `49c77b4`, `1154c37`); pass the `businessID` in and fetch narrowly instead.

**Scope every `@Query` over a growing table in the fetch, not in memory.** `Invoice`, `Client`, `Job` and `Contract` grow with use, so a bare `@Query private var invoices: [Invoice]` loads the whole account — including other businesses' rows — on every view update. Take the id as an `init` parameter and bind the query there:

```swift
init(businessID: UUID? = nil) {
    let scopedID = BusinessScoped.queryBusinessID(businessID)
    _invoices = Query(filter: #Predicate<Invoice> { $0.businessID == scopedID })
}
```

`BusinessScoped.queryBusinessID(_:)` maps `nil` to a constant that matches nothing — a predicate needs a concrete UUID at `init`, and a fresh `UUID()` there would re-fetch on every render. When the view already has a narrower key, prefer it: filter by `clientID` or `sourceBookingRequestId` rather than by business.

Two exceptions: `BusinessProfile` is one row per business, so leaving it unfiltered is fine; and a lookup of a single record by id should be a `FetchDescriptor` with `fetchLimit = 1` at the point of use, not a held query (see `AppTabView.invoice(withID:)`) — that is also more correct across a business switch, which an in-memory scan of a scoped array would miss.

### Estimates are Invoices

There is no `Estimate` model. An estimate is an `Invoice` with `documentType == "estimate"` (vs `"invoice"`), with its own lifecycle fields (`estimateStatus`: draft/sent/accepted/declined, `estimateAcceptedAt`, `estimateDeclinedAt`). ~55 sites branch on `documentType`. `EstimateToInvoiceConverter` handles conversion; `sourceEstimateId` records the link. Any list, filter, or count over invoices must decide explicitly which `documentType` it means.

### A finalized document stops tracking live records

Three things snapshot themselves so history stays readable, and they share one rule: while a document is a draft it follows the live record; once it is locked it keeps what it recorded.

- **Business identity** — `businessSnapshotData` / `businessSnapshotLockedAt`, locked via `InvoicePDFService`. Editing your profile doesn't change a past invoice's letterhead.
- **The client** — `clientSnapshotData`, decided by `ClientSnapshotPolicy`, resolved for display via `invoice.clientForRendering` / `displayClientName`. `Invoice.client` is a plain relationship with **no delete rule** — exactly one of the schema's 29 relationships has one (`Invoice.items`) — so deleting a client leaves its invoices alive with `client == nil`. Never read `invoice.client` when rendering or displaying who an invoice is for.
- **A signed contract** — `ContractSignLock` records `signedBodyHash` at signing; `Contract.markSigned` is the only way to set signed status, so the hash can't be forgotten. The backend enforces the same rules in `src/lib/contractSignLock.ts` and the two must agree on the hash (normalize CRLF, trim, SHA-256, hex).

`isBusinessInfoLocked` is the shared "is this finalized" predicate: snapshot lock record, or paid, or uploaded to the portal, or a sent/accepted/declined estimate.


### Money: integer cents are authoritative

`Invoice`'s `*Cents` accessors are the real computation — they round each line item to cents and then sum, which is what an itemized invoice adds up to. The `Double` accessors (`subtotal`, `taxAmount`, `total`) are display-only and derive from the cents via `Self.dollars(_:)`.

Never compute money the other way round. Summing unrounded line totals and rounding once at the end gives a different answer (three items at $0.335 → 1.005 vs 1.02), and when the two paths coexist the PDF and the checkout page disagree — which is exactly the bug `InvoiceMoneyTests` exists to prevent. When you need cents, read `invoice.totalCents`; don't write `Int((invoice.total * 100).rounded())`.

### Portal sync

`PortalBackend.swift` (~92 KB, one file) is the whole HTTP client for `portal.smallbizworkspace.com` — DTOs plus one method per backend endpoint. It authenticates with the `x-portal-admin` header from `PortalAdminKey.value`, read from `PortalSecrets.plist`.

Upload is dirty-hash-driven, tracked by fields on `Invoice`/`Contract`: `portalNeedsUpload`, `portalUploadInFlight`, `portalLastUploadedHash`, `portalLastUploadedBlobUrl`. `PortalAutoSyncService` computes a content hash, skips the upload when the hash is unchanged, reuses the existing blob URL when it can, and resets `portalNeedsUpload = true` on failure. When adding a field that should change the published document, add it to the hash function or the change will never sync.

Inbound flows: `EstimatePortalSyncService` polls every 90 s while active, and portal decisions also arrive as deep links handled by `PortalReturnRouter` / `NotificationRouter` / `EstimateDecisionSync`.

### Files subsystem

Two layers that must stay in sync: bytes on disk via `AppFileStore` (under Application Support, addressed by *relative* path), and the browsable index of `Folder` / `FileItem` models. `DocumentFileIndexService` writes a generated PDF and indexes it in one step, routing it into the job's `Invoices` / `Estimates` / `Contracts` folder; `RoutingAcceptanceTests` is what pins that placement.

**`AppFileStore` honors the `SBW_FILESTORE_BASE_URL` env var** to redirect storage to a temp dir — that's how tests avoid touching real Application Support. Set it in `setUpWithError` for any test that writes files.

### Navigation

`AppTabView` owns a separate `@State NavigationPath` *and* a `resetID` `UUID` per tab (dashboard/invoices/clients/more). Re-tapping a tab or a reset action swaps the `resetID` to rebuild the stack. Cross-cutting jumps go through `AppRouteCenter.shared.route(_:)`, a Combine bus with a small `AppRoute` enum, rather than passing bindings down.

Navigate by **ID, not by model object** (`f9f8b94`, `cbb4744`): push a `UUID` and let the destination fetch. Pushing SwiftData objects into a `NavigationPath` caused the crashes and freezes those commits fix.

## Conventions

- The source folder is **flat** — 206 Swift files in `SmallBiz Workspace/`, with only `Portal/`, `UI/SummaryKit/`, and `Insights/` grouped. New files go at the top level next to their peers.
- **Only the app target uses a filesystem-synchronized group.** A new file in `SmallBiz Workspace/` is picked up automatically, but `SmallBizWorkspaceTests/` still uses explicit `PBXFileReference` / `PBXBuildFile` entries — a new test file must be added to `project.pbxproj` in four places (build file, file reference, group membership, Sources phase) or it silently won't run. Watch for this: `xcodebuild test` reports `** TEST SUCCEEDED **` after executing 0 tests, so a missing test file looks like a pass.
- Views are large and self-contained by design (`InvoiceDetailView.swift` is ~97 KB, `BusinessProfileView.swift` ~52 KB). Extract when a change calls for it, but don't restructure a view file as a side errand.
- Shared summary/detail UI comes from `UI/SummaryKit` (`SummaryCard`, `SummaryHeader`, `SummaryRows`, `StatusChip`); theming from `SBWTheme.swift`. The app is locked to `.preferredColorScheme(.dark)`.
- Keep SwiftData work off the main thread for anything non-trivial. A long run of commits (`5768b3a`, `7c2a209`, `.tmp_build_*_freezefix.log`) exists purely to fix main-thread fetches in list and insights views.
- Swift language mode is 5 (not 6), though concurrency-warning cleanups have been done. `@MainActor` is applied to stores, view models, and services that touch `ModelContext`.

## Security: the portal admin key is committed

`SmallBiz Workspace/PortalSecrets.plist` holds a live production `PORTAL_ADMIN_KEY`, and **it is tracked in git and present on `origin/main`** (`github.com/2fs5fbf46s-cell/SimpleInvoice`). The `.gitignore` entry added in `8b1c3a2` has no effect because the file was already in the index.

That key is the `x-portal-admin` credential for every admin endpoint on the backend — bookings, notifications, push, portal seeding. Treat it as compromised: it needs rotating in Vercel, `git rm --cached` on the file, and history scrubbing. Until then, never echo the file's contents, and don't add new secrets beside it.
