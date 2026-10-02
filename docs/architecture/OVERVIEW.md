# TrailMetrics — Architecture Overview

TrailMetrics is a cross-platform activity tracker (Android + iOS) built with
Kotlin Multiplatform (KMP). This document describes the module graph, the
platform strategy, and the reasoning behind the key architectural decisions.
It is the entry point for any human or AI coding agent working on this
project — read this before touching any module.

## Platform strategy

- **Business logic, data, and navigation identity are shared** via KMP.
- **UI is 100% native per platform**: Jetpack Compose on Android, SwiftUI on
  iOS. Compose Multiplatform is a deliberate non-goal (see
  `ADR-001-no-compose-multiplatform.md`) — UI code never crosses the
  Android/iOS boundary, only the models and logic behind it do.
- Any module or file that imports `androidx.compose.*` is Android-only by
  definition and must never be added to a KMP module's `commonMain`.

## Module graph

```
                     +---------+
                     | domain  |  pure Kotlin, no Android/iOS deps
                     +----+----+
                          |
              +-----------+-----------+
              |                       |
         +----v----+             +----v----+
         |  data   |             |  core   |  commonMain only:
         |  (KMP)  |             |  (KMP)  |  AppRoute, RouteUiError
         +----+----+             +----+----+
              |                       |
              +-----------+-----------+
                          |
                     +----v----+
                     | shared  |  umbrella module: Koin composition
                     |  (KMP)  |  root + XCFramework export for iOS
                     +----+----+
                          |
              +-----------+-----------+
              |                       |
      +-------v--------+      +-------v--------+
      |  androidApp/*  |      |    iosApp/*    |
      |  app, feature-*,|     | TrailMetrics.  |
      |  core-ui        |     | xcodeproj +    |
      |  (Compose)      |     | Packages/*     |
      |                 |     | (SwiftUI, SPM) |
      +-----------------+     +----------------+
```

| Module | Platform | Role |
|---|---|---|
| `domain` | KMP (pure Kotlin) | Business models, use cases, repository interfaces. Zero Android/iOS dependency. |
| `data` | KMP | Repository implementations, Room, Ktor networking, platform-specific location/tracking services via expect/actual. |
| `core` | KMP (commonMain only) | Platform-agnostic navigation (`AppRoute`) and UI-adjacent error models (`RouteUiError`) — no UI framework of any kind. |
| `shared` | KMP | Umbrella module. Composes Koin DI graph (`initKoin()`), exports `domain` + `data` + `core` as a single `TrailMetricsShared.xcframework` for iOS. Uses SKIE for Swift-friendly Flow/coroutines interop. |
| `androidApp/app` | Android | Composition root: NavHost, Application class, DI wiring for Android-only (Compose UI) Koin modules. |
| `androidApp/feature-*` | Android | Feature modules (route, tracking, history) — Compose screens + ViewModels. |
| `androidApp/core-ui` | Android | Compose design system (Theme, Color, Type, MetricCell) and Google Maps Compose components. Deliberately NOT part of the KMP `core` module (see `ADR-003-core-ui-split.md`). |
| `androidApp/core-testing` | Android | Test fakes shared by two or more `feature-*` test source sets. Consumed only via `testImplementation`, so it's never in the APK. |
| `iosApp/TrailMetrics.xcodeproj` | iOS | Composition root: SwiftUI App struct, calls `doInitKoinIos()`. |
| `iosApp/Packages/SharedKit` | iOS (SPM) | Thin wrapper re-exporting `TrailMetricsShared.xcframework`. Every other iOS package depends on this, never the XCFramework directly. |
| `iosApp/Packages/<Feature>` | iOS (SPM) | One local Swift Package per feature (History, Route, Tracking), mirroring `androidApp/feature-*`. SwiftUI Views + `ObservableObject` ViewModels. |
| `iosApp/Packages/TestSupport` | iOS (SPM) | Test fakes and helpers (`waitUntil`) shared by two or more feature packages; the iOS equivalent of `androidApp/core-testing`. Linked only from each feature's `.testTarget`, never the app. |

## Dependency injection (Koin)

- `shared`'s `commonMain` defines `fun initKoin(appDeclaration: KoinAppDeclaration = {})`
  plus `expect val platformModules: List<Module>`.
- Android's `TrailMetricsApplication` calls `initKoin { androidContext(this); modules(routeModule, trackingUiModule, historyUiModule) }`
  — platform + shared modules come from `shared`, Compose-only UI modules are
  passed explicitly since `shared` has no knowledge of `androidApp/feature-*`.
- iOS's `TrailMetricsApp.init()` calls `KoinInitIosKt.doInitKoinIos()`.
- Because Koin's `get<T>()` is an inline reified function and cannot be
  exported to Swift, `shared/iosMain` exposes a `KoinHelper : KoinComponent`
  bridge class with concrete, non-generic getter functions per dependency
  that Swift code needs.

## Navigation

- `AppRoute` (in `core`'s `commonMain`) is the single source of truth for
  "what screens exist and what data they carry." It has zero dependency on
  any navigation framework.
- Android wires `AppRoute` into `androidx.navigation.compose`'s type-safe
  `composable<T>()` API directly (`androidApp/app/MainActivity.kt`).
- iOS is expected to consume `AppRoute` (exported to Swift as an enum via
  SKIE) with `NavigationStack`/`NavigationPath`.
- Android-only navigation plumbing (`NavTypes.kt` — custom `NavType`s for
  `Coordinates` — depends on `android.os.Bundle`) stays in `androidApp/app`
  and is never shared.

## iOS build integration

- `scripts/build-kmp-framework.sh` decides whether the shared XCFramework
  needs Gradle. It hashes the content of the Kotlin sources of `domain`,
  `data`, `core` and `shared` plus the Gradle build files, and runs
  `./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework` only when
  that hash changed or the XCFramework is missing. It writes its stamp only
  after Gradle succeeds.
- The shared `TrailMetrics` scheme runs the script as a Build pre-action.
  Xcode copies the XCFramework and compiles the Swift packages before any
  Run Script phase runs, so a phase alone cannot fix a stale framework in
  the same build.
- The target's "Build KMP Shared Framework" Run Script phase stays as a
  safety net (`alwaysOutOfDate`): if it had to rebuild, the pre-action
  didn't run, and it fails the build with a "build again" error. The
  TrailMetrics target sets `ENABLE_USER_SCRIPT_SANDBOXING = NO`, which this
  phase needs to run Gradle.
- `scripts/pre-push-check.sh` runs the same script before its iOS build.
- A per-user scheme in `xcuserdata` with the same name overrides the
  shared scheme and has no pre-action; delete it if present.
- Details: `tm-ios` ("Build integration") and `LEARNINGS.md` ("Xcode
  skipped the KMP build phase and linked a stale XCFramework").

## Coding standards and enforcement

Coding standards (naming, deprecated-API policy, module dependency rules,
etc.) are documented in the Skills under `.claude/skills/` (`tm-kmp-shared`,
`tm-android`, `tm-ios`, `tm-testing`) and are **enforced by tooling, not
just convention**:
- Android/Kotlin: Detekt (`config/detekt/detekt.yml`), run in CI (`ci.yml`).
- iOS/Swift: SwiftLint (`iosApp/.swiftlint.yml`), run in CI (`ci.yml`, iOS job).

Any coding agent (human or AI) working on this project must read the Skill
for every layer or platform it touches, plus `tm-pr-workflow`, before
writing code, and must not rely on lint/CI to catch violations
after the fact — the rules exist to make correctness the path of least
resistance, not a safety net.

## Related documents

- `docs/architecture/ADR-001-no-compose-multiplatform.md`
- `docs/architecture/ADR-002-shared-umbrella-module.md`
- `docs/architecture/ADR-003-core-ui-split.md`
- `.claude/skills/` — `tm-kmp-shared`, `tm-android`, `tm-ios`, `tm-testing`,
  `tm-pr-workflow`, `epic-orchestration`
- `LEARNINGS.md` (chronological gotchas log, complements this document)
