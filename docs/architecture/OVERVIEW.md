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
| `iosApp/TrailMetrics.xcodeproj` | iOS | Composition root: SwiftUI App struct, calls `doInitKoinIos()`. |
| `iosApp/Packages/SharedKit` | iOS (SPM) | Thin wrapper re-exporting `TrailMetricsShared.xcframework`. Every other iOS package depends on this, never the XCFramework directly. |
| `iosApp/Packages/<Feature>` | iOS (SPM) | One local Swift Package per feature (History, Route, Tracking), mirroring `androidApp/feature-*`. SwiftUI Views + `ObservableObject` ViewModels. |

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

- `iosApp/TrailMetrics.xcodeproj` has a Run Script build phase
  ("Build KMP Shared Framework") that hashes all `.kt`/`.kts` files under
  `domain/src`, `data/src`, `shared/src` and only re-runs
  `./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework` when that
  hash changes — see the script and required Xcode settings
  (`ENABLE_USER_SCRIPT_SANDBOXING = NO`) documented inline in the project's
  build phase and in `LEARNINGS.md`.

## Coding standards and enforcement

Coding standards (naming, deprecated-API policy, module dependency rules,
etc.) are documented in `docs/coding-standards/` and are **enforced by
tooling, not just convention**:
- Android/Kotlin: Detekt (`config/detekt.yml`), run in CI (`ci.yml`).
- iOS/Swift: SwiftLint (`.swiftlint.yml`), run in CI (`ci.yml`, iOS job).

Any coding agent (human or AI) working on this project must read
`docs/coding-standards/shared_conventions.md` plus the platform-specific
guide before writing code, and must not rely on lint/CI to catch violations
after the fact — the rules exist to make correctness the path of least
resistance, not a safety net.

## Related documents

- `docs/architecture/ADR-001-no-compose-multiplatform.md`
- `docs/architecture/ADR-002-shared-umbrella-module.md`
- `docs/architecture/ADR-003-core-ui-split.md`
- `docs/coding-standards/android_developer_guide.md`
- `docs/coding-standards/ios_developer_guide.md`
- `docs/coding-standards/shared_conventions.md`
- `docs/workflow/coding_agent_workflow.md`
- `LEARNINGS.md` (chronological gotchas log, complements this document)
