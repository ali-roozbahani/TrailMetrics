---
name: tm-kmp-shared
description: Use when changing or adding code in TrailMetrics `domain`, `data`, `core` or `shared` modules, when a feature needs a new use case, repository, Koin binding or `KoinHelper` getter, or when a change must work on both Android and iOS. Covers module boundaries, expect/actual, SKIE export, Koin composition and XCFramework rebuild. Not for Compose-only or SwiftUI-only work.
---

# TrailMetrics shared (KMP) layer

## Module boundaries (load-bearing)

- `domain`: pure Kotlin. No `android.*`, `androidx.*`, UIKit, Compose, SwiftUI. Holds models
  (`TrackingState`, `TrackingMetrics`, `Coordinates`, ...), use cases (`SaveActivityUseCase`),
  repository interfaces, session state machines (`TrackingSessionManager`).
- `data`: implements domain interfaces. Room, Ktor, platform services via expect/actual.
- `core` (commonMain only): `AppRoute`, `RouteError`/`RouteUiError`. Never a UI framework
  import. Compose belongs in `androidApp/core-ui`, never here (the Compose compiler plugin
  also compiles for iOS targets if applied in a commonMain module).
- `shared`: owns `initKoin()`. `shared` stays the only module that exports production API to
  iOS; `shared-uitest` builds only a test-only variant of the same framework, linked by UI-test
  builds and by the Swift package tests alone (ADR-002, "Amendment"). `shared-uitest` holds the
  iOS UI-test seam and the Kotlin test support of the Swift package tests (`SwiftTestFlow` and the
  rest, package `...uitest.testsupport`) and nothing else, and no production module depends on
  it. Test-only Kotlin never goes into `shared`: `scripts/check-production-framework.sh` fails
  the gate and CI when the production framework contains it.
- If a task seems to need a forbidden import, stop and report. Do not work around it.

## Existing error model — use it, don't replace it

TrailMetrics already has `RouteError` (domain-level) and `RouteUiError` (`toUiError()`
mapping in `core`), used across `TrackingSessionManager.locationIssues` and ViewModels on
both platforms. This is the project's error-handling convention. Do not introduce a
generic `Result<T, E>` wrapper or a different error hierarchy without being asked —
extend `RouteError`/`RouteUiError` with new cases instead.

## Where logic lives

- Derived state that both platforms need (metrics-from-state, calorie recompute,
  can-start/can-pause rules) belongs in `domain` as a pure function or use case, tested
  once. Do not re-implement it separately in an Android ViewModel and a Swift ViewModel.
  Known duplication today: metrics extraction from `TrackingState` and calorie recompute
  logic, both currently hand-written on each platform's ViewModel.
- Platform ViewModels only adapt shared logic to UI state/Action/Event. They do not own
  business rules.

## Time

Durations (elapsed time, speed windows, anything computed as a difference of two reads) are
measured with `Clock.elapsedRealtimeMillis()`, the monotonic clock that keeps counting while
the device sleeps. `Clock.nowMillis()` is only for wall-clock timestamps that are stored or
shown (`startedAtEpochMillis`, `endedAtEpochMillis`): the wall clock can jump either way when
the system time changes, so never subtract two `nowMillis()` reads.

## Adding a dependency iOS needs

1. Bind it in a Koin module inside `shared`/`data` (cross-platform modules only).
2. Add a concrete, non-generic getter to `KoinHelper` in `shared/iosMain`, e.g.
   `fun trackingSessionManager(): TrackingSessionManager`. `get<T>()` is inline reified
   and cannot be exported to Swift.
3. Swift resolves it via a default-parameter constructor:
   `init(trackingSessionManager: TrackingSessionManager = KoinHelper().trackingSessionManager())`
   — see `TrackingViewModel.swift` for the pattern used across all shared dependencies.

Android-only (Compose UI) Koin modules are NOT registered in `shared`; they're passed to
`initKoin { modules(...) }` in `androidApp/app/TrailMetricsApplication.kt`
(currently: `routeModule`, `trackingUiModule`, `historyUiModule`).

## SKIE and Swift-facing API design

- Kotlin sealed interfaces become Swift enums via `onEnum(of:)` (see `TrackingState` used
  as `switch onEnum(of: trackingState) { case .tracking(let data): ... }`). Keep sealed
  hierarchies flat and exhaustive-friendly.
- `Flow`/`SharedFlow` becomes `AsyncSequence`, consumed with `for await`. An
  `AsyncStream` has ONE consumer for its lifetime — never store a `Flow` as a `let`
  and hand out multiple `for await` loops on it. Use a fresh `makeStream()` +
  continuation per consumer, matching `TrackingViewModel.makeEventsStream()`.
- Kotlin coroutine scopes may run on `Dispatchers.Default`; resumption in Swift after
  `for await` is NOT guaranteed to land on the MainActor even inside an `@MainActor`
  class. Hop explicitly with `await MainActor.run { ... }` around any state mutation,
  as both `observeTrackingState()` and `observeLocationIssues()` do.
- Prefer domain types that cross cleanly (Long, Double, sealed types). Verify the
  inferred Swift type for anything generic before relying on it.

### `@Throws` policy (Kotlin called from Swift)

Kotlin/Native delivers to Swift only the exceptions a function lists in `@Throws` (plus
`CancellationException` for suspend functions); any other exception reaching the boundary
terminates the process. SKIE makes every `suspend fun` `async throws` in Swift, so `try await`
looks safe even when the Kotlin side declares nothing.
1. Every Kotlin function Swift calls (or a Swift fake implements) that can throw declares
   `@Throws`; suspend functions list `CancellationException` explicitly.
2. Failures the UI shows specifically are `RouteError`. A function declaring
   `@Throws(RouteError::class, ...)` maps every failure to a `RouteError`.
3. Persistence-backed functions declare `@Throws(Exception::class, CancellationException::class)`,
   never `Throwable` (an `Error` such as OutOfMemoryError should crash). No new `RouteError` cases
   for them; Swift shows `RouteUiErrorGeneral`.
4. Swift never drops an error: no `try?` hiding a failure, no `Task { try ... }` without `do/catch`.
5. After a failure, state stays consistent (nothing half-updated, no navigation).

Today: `GenerateClosedRouteUseCase`, `GetCurrentLocationUseCase` follow rule 2 (their
repositories return `RouteError` failures). `SaveActivityUseCase`, `UserProfileRepository` and
`ActivityHistoryRepository`'s suspend members follow rule 3. `observeActivities()` is a `Flow`,
which `@Throws` doesn't cover: a failing Flow terminates the iOS app (SKIE collects it in a
coroutine scope with no handler, and its Swift iterator `fatalError`s on the error). Swift
therefore doesn't iterate it directly: `ObserveActivitiesUseCase` (domain) maps each emission to
`ActivitiesUpdate.Loaded` and turns an `Exception` (never an `Error` or cancellation), thrown
when `observeActivities()` is called or while collecting, into one `ActivitiesUpdate.Failed`,
then completes; `invoke()` itself never throws. The iOS and Android `HistoryViewModel`s both
consume that. A new Flow that Swift iterates and that can fail needs the same treatment.

## Events that must not be silently dropped

`MutableSharedFlow(extraBufferCapacity = 1)` with no replay (as used for
`TrackingSessionManager.locationIssues`) drops an emission if nobody is currently
collecting. If you add a new one-shot signal a screen must eventually see, decide
deliberately: replay, a `Channel`-backed flow, or state — do not assume delivery.
Call this out explicitly in the PR description if you touch event-emitting code.

## Navigation and errors

- `AppRoute` (core/commonMain) is the single source of truth for destinations and their
  data. Android wires it into type-safe `composable<T>()`; iOS into `NavigationStack`.
  Never create a parallel route type in a feature.
- `RouteUiError` is the shared classification, mapped via `.toUiError()`. Android maps
  it to string resources; add new cases on both platforms together, never one without
  the other.

## Build integration

After changing `domain`, `data`, `core` or `shared`, iOS needs a rebuilt XCFramework.
`scripts/build-kmp-framework.sh` does this automatically (hash of the sources of the four
modules and `shared-uitest`, the Gradle build files, and which variant is in place: production,
or the UI-test variant of `shared-uitest` for `--variant uitest` and for the `Debug-UITest`
configuration, which selects the variant). The shared `TrailMetrics` scheme's Build pre-action and the
"Build KMP Shared Framework" phase run it on every Xcode build, and so does the gate. Do not
bypass it. Run the script yourself with `--variant uitest` before `xcodebuild test` inside an
iOS package: the package tests link the test-only variant (details in `tm-ios`).

## Changing the database schema (Room)

Installed apps keep their database file across updates, so an entity or stored-form change must
open every older database and keep its rows. The procedure, in order:

1. Change the entity (`data/src/commonMain/.../local/entity/`) or the converter
   (`local/database/Converters.kt`). A converter's stored form (`ActivityType`'s names, the
   coordinate-list JSON) is pinned in `ConvertersTest`; changing it is a schema change too.
2. Bump `version` in `@Database` (`TrailMetricsDatabase.kt`) from M to N = M + 1, and
   `CURRENT_DATABASE_VERSION` in the harness (`data/src/commonTest/.../local/database/FrozenDatabaseVersions.kt`).
3. Build (`./gradlew :data:testAndroidHostTest`): Room's KSP step exports `data/schemas/.../N.json`.
   Commit it. Never edit, delete or regenerate an existing schema file.
4. Write `MIGRATION_M_N` (a `val` or `object` extending `androidx.room3.migration.Migration`) in
   `data/src/commonMain/.../local/database/Migrations.kt` and add it to `appMigrations`, which
   `getRoomDatabase` adds to the builder. The app and the harness use the same list.
5. Add the harness case (`tm-testing`, "Migration cases (Room)"): the frozen fixture of version M
   if it is not there yet, and a case named for `MIGRATION_M_N` that opens it and asserts every
   row at N. The case must insert rows at M and assert them after migrating: only then does it
   show that no row is lost and the new or changed columns get the intended values. A case that
   only names the migration passes the schema check and proves nothing.
6. A destructive step (dropping a table or column, deleting or rewriting rows,
   `fallbackToDestructiveMigration`) and any change of the database file name
   (`DATABASE_FILE_NAME`, pinned by `DatabaseFileNameTest`), its directory or the driver is the
   human's decision: stop and report instead of doing it.

What catches what: `scripts/check-room-schema.sh --base` (gate and CI, every classification) fails
when an existing schema file is deleted or its `version` or `identityHash` changes (rule (a)), the
version goes down (b), a bump from M to N lacks `N.json`, `MIGRATION_M_N` under
`data/src/commonMain/.../local/database/` or a changed test under
`data/src/commonTest/.../local/database/` that names it (c), the current version has no schema
file (d), or a main source set calls `fallbackToDestructiveMigration` (e). Its
`--check-export-fresh` step after the build fails when the build rewrote or added a file under
`data/schemas/`: an entity change without a bump (step 2). A converter that keeps its column type
does not change the exported schema, so neither check sees a change of its stored form (step 1):
the harness case with a frozen fixture of the old form (step 5) and `tm-pr-review` item 12 catch
it. Both are text and path checks; whether the rows survive is the harness's job (step 5), and
whether its assertions are meaningful the reviewer's.

## Cross-platform change order

For a feature touching shared + both UIs: shared layer changes go in first and merge to
the epic branch; Android UI and iOS UI then proceed independently since they only touch
`androidApp/` and `iosApp/` respectively.

## Kotlin conventions (domain / data / core / shared)

The same Kotlin rules `tm-android` applies under `androidApp/` apply here too:
- Naming: Gradle modules lowercase and hyphenated; packages lowercase dot segments with no
  underscores. Classes/interfaces `PascalCase` with no `I` prefix
  (`ActivityHistoryRepository`, not `IActivityHistoryRepository`); functions/properties
  `camelCase`. Booleans read as questions (`isLoading`, `canStart`, `hasPermission`), never
  a bare noun. Test names are backtick sentences, never `test1` (see `tm-testing`).
- No deprecated APIs. These modules compile with `allWarningsAsErrors = true`, so a
  deprecation call fails the build. Use the replacement. If one is genuinely unavoidable
  (a third-party library with no replacement yet), suppress it narrowly at the call site
  with `@Suppress("DEPRECATION")` and a comment stating why, never at file or module
  level, and only with human approval. Don't mark your own APIs `@Deprecated` to phase
  them out; update the callers and delete the old API in the same change.
- No dead code: no commented-out blocks, no unused declarations or imports left behind
  after a refactor. Git history is the backup. Comments explaining *why* are welcome.

## Detekt reminders (CI-enforced, see `config/detekt.yml`)

No `println`/`print` (`ForbiddenMethodCall` — use the injected `Logger`), no
`kotlinx.coroutines.GlobalScope` (`ForbiddenImport`), `maxIssues: 0`. `TrackingSessionManager`
and `TrackingViewModel` have an explicit `LongParameterList` exclude — don't casually
extend that exclude list to other classes; if a class is growing too many parameters,
that's a signal to look at its responsibilities, not to suppress the rule.
