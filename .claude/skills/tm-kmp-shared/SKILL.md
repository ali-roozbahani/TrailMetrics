---
name: tm-kmp-shared
description: Use when changing or adding code in TrailMetrics `domain`, `data`, `core` or `shared` modules, when a feature needs a new use case, repository, Koin binding or `KoinHelper` getter, or when a change must work on both Android and iOS. Covers module boundaries, expect/actual, SKIE export, Koin composition and XCFramework rebuild. Not for Compose-only or SwiftUI-only work.
---

# TrailMetrics shared (KMP) layer

## Module boundaries (load-bearing)

- `domain`: pure Kotlin. No `android.*`, `androidx.*`, UIKit, Compose, SwiftUI, Room or Ktor type.
  Holds models (`TrackingState`, `TrackingMetrics`, `Coordinates`, ...), use cases
  (`SaveActivityUseCase`), repository interfaces, session state machines (`TrackingSessionManager`).
- `data`: implements domain interfaces. Room, Ktor, platform services via expect/actual.
- The dependency direction is presentation to `domain` to nothing, and `data` to `domain`: `domain`
  imports no `data`, `shared` or UI type, and a class takes a `domain` interface, not the `data`
  class that implements it. Enforced: the Gradle module graph and reviewer only for an import or a
  parameter type. Violation: `blocking`.
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

## Existing error model — use it, don't replace it

TrailMetrics already has `RouteError` (domain-level) and `RouteUiError` (`toUiError()`
mapping in `core`), used across `TrackingSessionManager.locationIssues` and ViewModels on
both platforms. This is the project's error-handling convention. A custom two-parameter
`Result<T, E>` is not added, nor a different error hierarchy, without being asked;
`kotlin.Result<T>`, as `LocationRepository` and `DirectionsRepository` return it, is the current
convention. Extend `RouteError`/`RouteUiError` with new cases instead.

## Where logic lives

- Derived state that both platforms need (metrics-from-state, calorie recompute,
  can-start/can-pause rules) belongs in `domain` as a pure function or use case, tested
  once. Do not re-implement it separately in an Android ViewModel and a Swift ViewModel.
  Known duplication today: metrics extraction from `TrackingState` and calorie recompute
  logic, both currently hand-written on each platform's ViewModel.
- Platform ViewModels only adapt shared logic to UI state/Action/Event. They do not own
  business rules.
- One reason to change per class. Enforced: detekt `TooManyFunctions` and `LongParameterList`
  (`tm-android`, "Detekt") are the mechanical signal; a class that mixes state, IO and formatting is
  the judgement one, reviewer only. Violation: `important`.
- Never an `is`/`as` cast on an abstraction to reach a concrete type, and never an interface method
  that an implementer leaves empty or throws `NotImplementedError` from (split the interface).
  Enforced: reviewer only. Violation: `important`.
- Crashes, ANR, exceptions, dispatchers, process death, leaks and performance: `tm-robustness`.

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
`initKoin { modules(...) }` in `androidApp/app/TrailMetricsApplication.kt`.
Currently they are `appModule`, `routeModule`, `trackingUiModule` and `historyUiModule`.

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
6. New Swift-visible API that needs no policy change: a data class, an enum case or a read-only
   `StateFlow`/`val` property on a domain type Swift already uses, and a parameter or return type
   added to (or swapped on) a function that already declares its `@Throws` or cannot throw. Allowed
   when (a) no existing `@Throws` is removed or changed, (b) a new function that can throw follows
   rules 1 to 3, (c) a new `Flow` that Swift iterates and that can fail gets the
   `ObserveActivitiesUseCase` treatment below (a `StateFlow` that never fails needs none), (d) the
   Swift fakes and callers are updated in the same PR, and (e) the PR description lists each new
   Swift-visible name under the heading `Swift-visible API`. Removing or changing a `@Throws` and a
   new failing Flow Swift iterates stay an escalation. A new getter on `KoinHelper` (step 2 of
   "Adding a dependency iOS needs") does not escalate when all of these hold: (a) it is concrete
   and non-generic, and its body only resolves the binding the way the neighbouring getters do
   (`get()` or their `by inject()` property), no other logic; (b) the binding it returns is added
   in the same PR in a `shared`/`data` Koin module (step 1); (c) `KoinGraphCheck` and the Swift
   fakes and callers are updated in the same PR; (d) the PR description lists the getter under
   `Swift-visible API`. Still an escalation: removing, renaming or changing an existing getter, a
   getter with logic, and any other change to `KoinHelper`, to `KoinInit`'s module list beyond
   adding the binding of (b), or to how Koin starts.

Today: `GenerateClosedRouteUseCase`, `GetCurrentLocationUseCase` follow rule 2 (their
repositories return `RouteError` failures). `SaveActivityUseCase`, `UserProfileRepository` and
`ActivityHistoryRepository`'s suspend members follow rule 3. `UserProfileRepository.getUserProfile`
returns `null` for "nothing saved" and throws `StoredUserProfileUnreadableException` (an `Exception`,
so rule 3 covers it) for a stored value that cannot be decoded; the value stays in storage until a
new profile overwrites it. `observeActivities()` is a `Flow`,
which `@Throws` doesn't cover: a failing Flow terminates the iOS app (SKIE collects it in a
coroutine scope with no handler, and its Swift iterator `fatalError`s on the error). Swift
therefore doesn't iterate it directly: `ObserveActivitiesUseCase` (domain) maps each emission to
`ActivitiesUpdate.Loaded` and turns an `Exception` (never an `Error` or cancellation), thrown
when `observeActivities()` is called or while collecting, into one `ActivitiesUpdate.Failed`,
then completes; `invoke()` itself never throws. The iOS and Android `HistoryViewModel`s both
consume that. A new Flow that Swift iterates and that can fail needs the same treatment.

## iOS location (L1)

Decided by the owner and in the code since `ios-always-location-removal`: `IosLocationRepositoryImpl` requests
when-in-use authorization only, and `Info.plist` has no Always usage string.

- The app asks for when-in-use authorization only, and tracks in the background through the `location`
  background mode (`UIBackgroundModes` in `Info.plist`) with `allowsBackgroundLocationUpdates = true`
  while a session runs. A session starts while the app is in the foreground.
- No `requestAlwaysAuthorization()` and no `NSLocationAlwaysAndWhenInUseUsageDescription` unless a
  feature that needs the app relaunched after termination is built; that is an owner decision with its
  own App Review note.
- While a session runs: `allowsBackgroundLocationUpdates` true, `pausesLocationUpdatesAutomatically`
  false, `activityType` fitness; all three are put back when it ends (`applyBackgroundTracking`,
  proved by `BackgroundTrackingSettingsTest`).
- The authorization status is read at the use site (`ensureLocationPermission`) and never cached; a
  refusal is `RouteError.MissingLocationPermission`, as on Android.
- A simulator cannot show the behavior with the screen off, so no test proves it: a change here
  ends with a short device check by the owner.
- Enforced: reviewer only. Violation: `important`.

## Cancellation

A `catch` that can see `CancellationException` rethrows it (`SafeApiCall.kt` is the pattern), and
`runCatching` is not used around suspend calls unless it rethrows it.

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

## KMP module build setup

The four KMP modules share one build shape. `domain/build.gradle.kts` is the template: copy its
structure for a new module and take the iOS targets and KSP lines from `data`.

- Plugins: `org.jetbrains.kotlin.multiplatform` and `com.android.kotlin.multiplatform.library` (AGP
  9.2.1). Never `com.android.library` or `com.android.application` next to the KMP plugin.
- Android settings sit in `kotlin { android { namespace; compileSdk; minSdk; compilerOptions { jvmTarget } } }`.
  Write them there, not in a top-level `android {}` block and not in `androidTarget {}`.
- `withHostTestBuilder {}.configure {}` in that block creates the `androidHostTest` source set. Its
  dependencies go in `getByName("androidHostTest") { dependencies { ... } }` (see `data`); `commonTest`
  runs on the Android host and on the iOS simulator.
- A new module declares `iosArm64()` and `iosSimulatorArm64()` and no `iosX64()`. Room 3.0.2 publishes no
  iosX64 artifact (`LEARNINGS.md`). The Room processor goes to each target on its own, as in `data`:
  `add("kspAndroid", ...)`, `add("kspIosArm64", ...)`, `add("kspIosSimulatorArm64", ...)`, never a broad `ksp(...)`.
- Versions come from `libs.versions.toml`, and a constant that used to be `BuildConfig` comes from BuildKonfig
  (`data`): these modules have no `BuildConfig` class.
- Enforced: reviewer only. Violation: `important`.

## Kotlin/Native build cost

Measured on 2026-11-17 (Apple M4, 16 GB, Kotlin 2.4.10, warm `~/.konan` and Gradle caches, fresh clone of
`main` at `ed7943f`, `scripts/heavy-run.sh ./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework
:shared:linkReleaseFrameworkIosArm64 :domain:linkDebugTestIosX64`): 66 s wall time.

- A debug framework link takes about 11 s per slice, with about 6 s of compile and 4 s of KSP before it; the
  release link of one slice takes 52 s, about 4.7 times the debug link; `:domain:linkDebugTestIosX64` takes 19 s.
- Static archive sizes: 70.5 MB per debug slice, 22.6 MB for release arm64; the debug XCFramework is 147 MB.
  The Swift header `TrailMetricsShared.h` has 13,691 lines and 393 Objective-C types, about 190 of them from
  Ktor, kotlinx, Koin, Room and the `data` internals.
- Since `shared` and `shared-uitest` stopped exporting `:data`, the same header has 6,263 lines and 212 declarations
  (`@interface` and `@protocol` lines; the 393 above counts unique types, the same count gives 402 before), and the debug
  XCFramework is 140 MB instead of 148 MB. A Swift test that needs a real `data` object takes it from a factory in
  `shared-uitest` (`SwiftTestRepositories`). Never export `:data` from a framework again: its Ktor, kotlinx, Koin and Room
  types are not API for Swift. Enforced: reviewer only. Violation: `important`.
- CI's `ios-build` job does not cache `~/.konan`, so every run downloads the Kotlin/Native bundle.
- A `~/.konan` cache was tried on 2026-11-17 (PR #330, closed): the restore took 22 to 24 s and the post-job step about
  6 s, while the download it saves took about 8 s, and the framework step showed no gain.
- The Gradle daemon in CI runs on the runner's Temurin 21 (21.0.13 on 2026-11-17); only the launcher is JDK 17, the
  one `setup-java` installs.
- A change to the build (targets, exports, caches, flags) is measured: run the real command twice before and
  twice after, on the same machine and state, under `scripts/heavy-run.sh`, and put both numbers in the PR
  (the first run fills caches). Enforced: reviewer only. Violation: `important`.
- A faster local loop changes nothing that CI or a Release build produces. Enforced: reviewer only. Violation: `blocking`.
- Open work is on the board: `release-build-links-debug-xcframework`, `ios-simulator-only-framework-slice`,
  `swift-api-header-dump-in-gate`, `ios-ci-package-tests-duration`.
- Revisit when: Room publishes an iosX64 artifact, or Intel simulators are wanted again; the no-iosX64 rule for new
  modules then changes.

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
5. Add the frozen fixture of version M (if missing) and the case named for `MIGRATION_M_N`:
   `tm-testing`, "Migration cases (Room)" is the canonical statement of what they must contain.
6. A destructive step (dropping a table or column, deleting or rewriting rows,
   `fallbackToDestructiveMigration`) and any change of the database file name
   (`DATABASE_FILE_NAME`, pinned by `DatabaseFileNameTest`), its directory or the driver is the
   human's decision: stop and report instead of doing it.
7. The agent never merges a PR that changes the schema or a converter's stored form (owner decisions of
   2026-11-16). Their marks, `data/schemas/`, `Migrations.kt`, `TrailMetricsDatabase.kt` (the `@Database`
   version and entity list) and `Converters.kt` (its stored form exports no schema file and bumps no version,
   yet can make existing data unreadable), are protected paths in `.github/CODEOWNERS`, so such a PR is the
   owner's to merge even when it touches nothing else protected: build it through the gate as usual, post
   the Merge check (condition 6 is "no", `tm-agent-loop`, section 8) and hand it over. A change of a DAO, a
   mapper, a repository, the builders or a test (`ConvertersTest` included) stays open; an entity change
   reaches the protected files because it needs the bump (step 2).

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

Naming, no deprecated APIs (these modules compile with `allWarningsAsErrors = true` too) and no
dead code: the Kotlin rules in `tm-android` ("Naming (Kotlin)", "No deprecated APIs (Kotlin)",
"No dead code") apply here unchanged.

## Detekt

CI-enforced: config `config/detekt/detekt.yml`, rules and limits in `tm-android` ("Detekt").

## Known deviations in the current code

Don't copy these as a pattern for new code.
- `IosTrackingServiceLauncher` takes the concrete `IosLocationRepositoryImpl`, not `LocationRepository`,
  because `setBackgroundUpdatesEnabled` is not on the interface (see "Module boundaries";
  `ios-launcher-depends-on-concrete-location-repository`).
