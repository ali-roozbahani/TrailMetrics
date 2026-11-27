---
name: tm-kmp-shared
description: Use when changing or adding code in TrailMetrics `domain`, `data`, `core` or `shared` modules, when a feature needs a new use case, repository, Koin binding or `KoinHelper` getter, or when a change must work on both Android and iOS. Covers module boundaries, expect/actual, SKIE export, Koin composition and XCFramework rebuild. Not for Compose-only or SwiftUI-only work.
---

# TrailMetrics shared (KMP) layer

## Topic files

Read each file when the task or the diff reaches its topic, not before; a reviewer reads it for a diff that touches the
topic. Section headings are unchanged, so a reference to `tm-kmp-shared`, "<heading>", is found in this file or in the
file named here.

| File | Read it when |
|---|---|
| `swift-interop.md` ("SKIE and Swift-facing API design", "`@Throws` policy", "iOS location (L1)") | a Kotlin type, function or `Flow` is visible to Swift (anything in `shared`, a `KoinHelper` getter, a public type of `domain`, `core` or `data` that Swift uses), or iOS location code changes |
| `kmp-build.md` ("Build integration", "KMP module build setup", "Kotlin/Native build cost") | a change touches a `build.gradle.kts` of `domain`, `data`, `core`, `shared` or `shared-uitest`, a target, an export, the XCFramework build or a cache |
| `room-schema.md` ("Changing the database schema (Room)") | a change touches an entity, a converter, a Room version, a migration or `data/schemas/` |


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
  The metrics and the calories of a `TrackingState` come from `TrackingMetricsUseCase`; the
  controls (start, pause, resume, stop, save, discard) come from `availableControls`, which both ViewModels ask.
- Platform ViewModels only adapt shared logic to UI state/Action/Event. They do not own
  business rules.
- One reason to change per class. Enforced: detekt `TooManyFunctions` and `LongParameterList`
  (`tm-android`, "Detekt", `kotlin-conventions.md`) are the mechanical signal; a class that mixes state, IO and formatting is
  the judgement one, reviewer only. Violation: `important`.
- Never an `is`/`as` cast on an abstraction to reach a concrete type, and never an interface method
  that an implementer leaves empty or throws `NotImplementedError` from (split the interface).
  Enforced: reviewer only. Violation: `important`.
- Crashes, ANR, exceptions, dispatchers, process death, leaks and performance: `tm-robustness`.

## User-visible text

- No text the user reads is written in code, in any module of either platform (owner decision of 2026-11-25):
  it comes from the platform's resources, Android `strings.xml` and the iOS String Catalog (`tm-ios`,
  "Strings", `strings-and-accessibility.md`). User-visible text is anything shown on a screen, in a
  notification, a widget or a Live Activity, or read out by accessibility: labels, messages, titles, unit
  words, placeholders.
- `domain`, `data` and `core` do not build sentences: they hand over a typed value (a sealed or enum case, a
  number, a date), and each platform builds the text from its own resources. `RouteError` to `RouteUiError`,
  mapped to `strings.xml` on Android and to the catalog on iOS, is the pattern. Android-only code in `data`
  (`androidMain`, the tracking service's notifications) keeps its text in `data`'s own Android resources
  (`data/src/androidMain/res/values/strings.xml`).
- Not user-visible text: log messages, exception messages, identifiers, keys, test code and fakes.
- Why: a text in code cannot be translated, and a sentence built in shared code cannot follow each
  platform's resources. Example: `RouteUiError`. Enforced: reviewer only (`tm-pr-review`, item 2).
  Severity: blocking for a new text in code. The existing ones are known deviations (below).

## Exhaustive `when` over a sealed type

- A `when` over a sealed type or an enum names every case and has no catch-all `else`; a case that is
  ignored on purpose is named with the others (`Idle, Finished -> currentState`). This holds for the
  `TrackingState` state machine too: each handler names the states it ignores. Why: a new case then
  fails to compile where it needs a decision, instead of being ignored without a sound, which for a
  recorded session means a handler that drops it. Example: `UpdateTrackingStateUseCase` (each handler names
  the states it ignores). Enforced: reviewer only (the
  compiler checks a `when` expression only while it has no `else`). Severity: important. Not a finding:
  an `else` over a number range, a string, a subjectless `when`, or an enum that a platform defines.

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

## Cross-platform change order

For a feature touching shared + both UIs: shared layer changes go in first and merge to
the integration branch of the epic; Android UI and iOS UI then proceed independently since they only touch
`androidApp/` and `iosApp/` respectively.

## Kotlin conventions (domain / data / core / shared)

Naming, no deprecated APIs (these modules compile with `allWarningsAsErrors = true` too) and no
dead code: the Kotlin rules in `tm-android` (`kotlin-conventions.md`: "Naming (Kotlin)", "No deprecated APIs (Kotlin)",
"No dead code") apply here unchanged.

## Detekt

CI-enforced: config `config/detekt/detekt.yml`, rules and limits in `tm-android` ("Detekt", `kotlin-conventions.md`).

## Known deviations in the current code

Don't copy these as a pattern for new code.
- `MetricsFormatter` (`formatDistance`, `formatSpeed`, `formatCalories`) returns finished texts with unit words
  and placeholders ("1.50 km", "-- km/h"), which both platforms show (board: `shared-metrics-formatter-user-visible-strings`,
  `ios-hardcoded-number-formatting`).
