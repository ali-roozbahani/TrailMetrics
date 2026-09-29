---
name: tm-ios
description: Use when writing or changing iOS code in TrailMetrics under iosApp/ — SwiftUI views, Swift ViewModels, SPM feature packages, KoinHelper resolution, AppRoute navigation, the Xcode project or its build phases. Covers the ViewModel/View shape, SKIE interop from Swift, the composition root, XCFramework build integration, Swift naming/deprecation/dead-code rules and SwiftLint. Not for domain/data/core/shared Kotlin (see tm-kmp-shared) or for test code (see tm-testing).
---

# TrailMetrics iOS

This skill is the source of truth for iOS conventions (it replaced the retired
`ios_developer_guide.md` and `shared_conventions.md`). It records both the rules and what the
current code under `iosApp/` actually does. Where they differ, the code wins for "what
exists", the rules here win for "what new code should look like".

## Architecture

- One local Swift Package per feature under `iosApp/Packages/<Feature>/` (`History`,
  `Route`, `Tracking`), mirroring `androidApp/feature-*`. Copy an existing `Package.swift`
  (`swift-tools-version: 5.9`, `platforms: [.iOS(.v17)]`, one library product, one target)
  rather than hand-rolling one.
- Every feature package depends on `SharedKit`, never on `TrailMetricsShared.xcframework`
  directly. `SharedKit` is just `@_exported import TrailMetricsShared`, so Swift files
  `import SharedKit` — never `import TrailMetricsShared`.
- `DesignSystem` already exists (`Color.trailGreen`, `.trailRed`, ...). SwiftUI components used by 2+ features go there; don't
  create a second shared UI package.
- Feature packages do not depend on each other. Cross-feature navigation is wired in the
  app target (`iosApp/TrailMetrics/ContentView.swift`), not inside a feature.
- The only third-party dependency is `ios-maps-sdk` (GoogleMaps) in feature packages that
  render maps. Never add another package dependency unless the task names it.
- `iosApp/TrackingWidget/` is the Live Activity widget extension. It is a separate target,
  but SwiftLint and the iOS build still cover it.

## ViewModel shape

```swift
@MainActor
public class HistoryViewModel: ObservableObject {
    @Published public var activities: [ActivityRecord] = []
    @Published public var isLoading = true

    private let activityHistoryRepository: ActivityHistoryRepository

    public init(activityHistoryRepository: ActivityHistoryRepository = KoinHelper().getActivityHistoryRepository()) {
        self.activityHistoryRepository = activityHistoryRepository
    }

    public func observe() async {
        for await activities in activityHistoryRepository.observeActivities() { ... }
    }
}
```

- `@MainActor class <Feature>ViewModel: ObservableObject` with `@Published` state. This is
  the Swift equivalent of Android's `StateFlow<UiState>`, written natively in Swift and not
  shared via KMP (ADR-001). Use `public private(set)` for state the View must not write
  (see `TrackingViewModel`).
- Dependencies come in through a default-parameter `init` resolving from `KoinHelper()`,
  so previews and tests can pass a fake. Never call `KoinHelper()` anywhere except in a
  default argument or the composition root.
- Derived booleans (`canStart`, `canGenerateRoute`, `isEmpty`) are computed properties on
  the ViewModel, not logic in the View. If Android needs the same rule too, it belongs in
  `domain` (see `tm-kmp-shared`, "Where logic lives").
- One-shot signals (errors, navigation requests, dismiss) go through a
  `<Feature>UiEvent` enum and a `makeEventsStream()` factory that returns a **new**
  `AsyncStream` each time (see `RouteViewModel`/`TrackingViewModel`). Don't store a single
  `let events` stream: an `AsyncStream` has one consumer for its whole life, and a cancelled
  `.task` (screen covered by a push) leaves it dead the next time the view appears.
- iOS is **not** part of the Android MVI migration. iOS ViewModels expose intent methods
  (`onGenerateRouteClicked()`, `onMapTapped(_:)`). Keep that style. Some existing methods
  take completion closures (`TrackingViewModel.onFinishClicked(snapshotFilePath:onSaved:)`,
  `DetailsViewModel.onDeleteConfirmed(onDeleted:)`). For new code, prefer a `UiEvent` case,
  but don't rewrite existing closures unless the task asks for it.

## Koin / KoinHelper

- `TrailMetricsApp.init()` is the only place that calls `KoinInitIosKt.doInitKoinIos()`.
  Never call it from a View's `init` (SwiftUI can re-run it, starting Koin twice and crashing).
- A new dependency needed from Swift requires a new concrete getter on `KoinHelper`
  (`shared/src/iosMain/.../KoinHelper.kt`), because `get<T>()` is inline reified and doesn't
  export. That is a `shared` change, so follow `tm-kmp-shared` for it.
- Getter naming on `KoinHelper` is inconsistent today (`getActivityHistoryRepository()` vs
  `trackingSessionManager()`). Call whatever exists; don't rename existing getters as a side
  effect.

## SKIE interop from Swift

- A Kotlin `Flow` arrives as an `AsyncSequence`. Consume it with `for await`, driven from
  the View's `.task { }`, not an `.onAppear`/`.onDisappear` pair. The simplest form is
  `HistoryView`: `.task { await viewModel.observe() }`. Cancellation then comes free with the
  view lifecycle.
- If a ViewModel must own the loop itself (for example `TrackingViewModel` observes from
  `init`), store the `Task`, capture `[weak self]`, and cancel it deterministically (`deinit`
  plus the stop path).
- Resumption after `for await` is **not** guaranteed to be on the MainActor, even inside an
  `@MainActor` class, because Kotlin scopes can run on `Dispatchers.Default`. Wrap state
  mutations in `await MainActor.run { ... }` as `observeTrackingState()` does.
- Kotlin sealed types: `switch onEnum(of: value) { case .tracking(let data): ... }`. Keep
  the switch exhaustive so a new Kotlin case breaks the Swift build.
- Kotlin exceptions reach Swift as `NSError` with the Kotlin value in
  `userInfo["KotlinException"]`. See the `underlyingRouteError` extension in
  `RouteViewModel.swift`, and map to `RouteUiError` via `.toUiError()` with
  `RouteUiErrorGeneral.shared` as the fallback.
- Generic collections crossing the bridge: check the inferred Swift type rather than
  assuming it (`HistoryViewModel`'s `[ActivityRecord]` is the worked example).

## Navigation (AppRoute + NavigationStack)

- `AppRoute` (from `core`, bridged by SKIE, e.g. `AppRouteTracking`,
  `AppRouteActivityDetails`) is the single source of destinations and their data. Never
  define a Swift-only route enum.
- Each tab owns a `NavigationStack(path:)` with a `NavigationPath` in `ContentView.swift`.
  Feature views request navigation through a closure parameter (`HistoryView(onActivitySelected:)`,
  `RouteView { startPoint, plannedRoutePoints, activityType in ... }`). They don't push
  onto the path themselves.
- Don't push a bridged `AppRoute` value directly. Wrap it in a private UUID-keyed
  `Hashable` destination struct (`TrackingDestination`, `ActivityDetailsDestination`).
  Bridged routes use structural equality, so pushing a value equal to the one just popped
  is silently ignored by `NavigationPath`.
- Use `.navigationDestination(for:)`, not `NavigationLink(destination:)` wiring and not the
  deprecated `NavigationView`.

## SwiftUI views

- Views are `struct`s with no business logic. They read `@Published` state, call ViewModel
  methods, and do trivial formatting at most.
- The View owns its ViewModel as `@StateObject private var viewModel`. When the ViewModel
  needs init arguments, use `_viewModel = StateObject(wrappedValue: ...)` in the View's
  `init` (see `DetailsView`, `TrackingView`). Don't pass a ViewModel down the view tree.
  Child views get plain values and closures (`ActivityRow(activity:onDeleteClicked:)`).
- `@State` is only for view-local UI state (a pending-delete alert target, a local
  `NavigationPath`), not application state.
- Consume events in `.task { for await event in viewModel.makeEventsStream() { handle(event) } }`
  with an exhaustive `switch` in `handle(_:)`.
- Colors come from `DesignSystem` (`Color.trailGreen`); no ad-hoc RGB literals in features.
- Add a `#Preview` for new screens and reusable components. Use the ViewModel's
  default-parameter `init` to inject fakes where a live Koin graph isn't available.

## Build integration (XCFramework Run Script)

- The `TrailMetrics` target has a "Build KMP Shared Framework" Run Script phase that runs
  before `Sources`. It hashes the mtime and path of every `*.kt`/`*.kts` under
  `domain/src data/src shared/src`, compares against `shared/build/.xcode_kmp_stamp`, and
  runs `./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework` only when the hash
  changed. `SharedKit/Package.swift` points at the **debug** XCFramework output.
- It does **not** re-run for:
  - `core/src` changes, even though `shared` exports `core` (`AppRoute`, `RouteUiError`).
    This is a known gap.
  - Gradle files outside those `src` dirs (`shared/build.gradle.kts`, SKIE/export config,
    `gradle/libs.versions.toml`).

  After changing any of these, run the Gradle task manually (or delete the stamp file)
  before building in Xcode. Don't "fix" the phase as a side effect of an unrelated task.
  Report it instead.
- Never disable, reorder or bypass the phase.
- "Missing/stale symbol from `TrailMetricsShared`" right after a Kotlin change: first check
  whether the phase ran (Report Navigator → latest build → "Build KMP Shared Framework") and
  whether the change was in one of the unhashed paths above.
- `./gradlew clean` wipes the XCFramework; the next Xcode build has to regenerate it.

## Naming (Swift)

- Types `PascalCase`, functions/properties `camelCase`. Protocols carry no `I` prefix
  (`ActivityHistoryRepository`, not `IActivityHistoryRepository`).
- SPM packages and Swift modules are `PascalCase` single words (`History`, `DesignSystem`).
  The Kotlin "lowercase, no underscores" rule applies to Kotlin packages and Gradle modules;
  the Swift form of it is: no underscores or hyphens in package names.
- Per-feature types: `<Feature>View`, `<Feature>ViewModel`, `<Feature>UiEvent`.
  Extension files: `Type+Purpose.swift` (`RouteUiError+Message.swift`,
  `Color+TrailMetrics.swift`).
- Booleans read as questions: `isLoading`, `canStart`, `hasReachedDestination`. Never a bare
  noun.
- Identifiers are at least 3 characters (`id` is the one exception, enforced by
  `identifier_name`), so no `vm`, `i` or `e`.
- Test functions: `func test_savesActivity_recalculatesCalories()`, never `test1`.

## No deprecated APIs (Swift)

- Never call anything marked `@available(*, deprecated)`, or anything deprecated at or below
  the iOS 17 deployment target. Xcode reports these only as warnings, and SwiftLint doesn't
  catch them, so read the build log. Examples that matter here: `NavigationView` →
  `NavigationStack`; single-parameter `.onChange(of:perform:)` → the two-parameter
  `.onChange(of:) { oldValue, newValue in }` form already used in `TrackingView`;
  `NavigationLink(isActive:)` → `navigationDestination`.
- Fix the call rather than silencing it. Swift has no narrow call-site suppression: marking
  your wrapper `@available(*, deprecated)` only moves the warning to its callers. If a
  deprecation is genuinely unavoidable, stop and report it instead of wrapping it.
- Don't mark your own APIs `@available(*, deprecated)` to phase them out. Update the callers
  and delete the old API in the same change.

## No dead code

- No commented-out code, no unused types, functions, properties or `private` helpers left
  behind after a refactor. Git history is the backup.
- No unused imports (`unused_import` is enabled). Import `SharedKit`, not
  `TrailMetricsShared`.
- Explanatory comments are welcome. This codebase documents *why* at length (see the
  `TrackingDestination` and `makeEventsStream()` comments). Commented-out code is not.

## SwiftLint (CI-enforced, `--strict`)

Config: `iosApp/.swiftlint.yml`. Run it from `iosApp/` with `swiftlint lint --strict`. It
runs in `scripts/pre-push-check.sh` (whenever `iosApp/`, `domain/`, `data/`, `core/` or
`shared/` changed) and in the CI macOS job, followed by an `xcodebuild` simulator build.

- `--strict` promotes every warning to a failure. The `warning` thresholds are the real
  limits: line length 120, function body 60 lines, type body 300 lines, cyclomatic
  complexity 15.
- `force_unwrapping`, `force_cast` and `force_try` are errors. Restructure with
  `guard let`/`if let`, `as?` with explicit `else` handling, or `do`/`catch`.
- Opt-in rules on top of the defaults: `force_unwrapping`, `unused_import`, `explicit_init`,
  `closure_spacing`, `empty_count` (use `.isEmpty`), `fatal_error_message`.
- Don't add `// swiftlint:disable` comments and don't edit `.swiftlint.yml` to make a
  violation pass. Refactor instead, or ask if the rule genuinely doesn't fit. A suppression
  needs explicit human approval and a stated reason.
