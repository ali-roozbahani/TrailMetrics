---
name: tm-ios
description: Use when writing or changing iOS code in TrailMetrics under iosApp/ — SwiftUI views, Swift ViewModels, SPM feature packages, KoinHelper resolution, AppRoute navigation, the Xcode project or its build phases. Covers the ViewModel/View shape, SKIE interop from Swift, the composition root, XCFramework build integration, Swift naming/deprecation/dead-code rules and SwiftLint. Not for domain/data/core/shared Kotlin (see tm-kmp-shared) or for test code (see tm-testing).
---

# TrailMetrics iOS

This skill is the source of truth for iOS conventions (it replaced the retired
`ios_developer_guide.md` and `shared_conventions.md`). It records both the rules and what the
current code under `iosApp/` actually does. Where they differ, the code wins for "what
exists", the rules here win for "what new code should look like".

## Topic files

Read each file when the task or the diff reaches its topic, not before; a reviewer reads it for a diff that touches the
topic. Section headings are unchanged, so a reference to `tm-ios`, "<heading>", is found in this file or in the file
named here.

| File | Read it when |
|---|---|
| `strings-and-accessibility.md` ("Strings", "Accessibility", "Numbers, units and durations") | a change adds or edits user-visible text, a String Catalog, an accessibility label or trait, or formats a number, a unit or a duration |
| `uikit-and-concurrency.md` ("Wrapping a UIKit view (the maps)", "Swift concurrency settings per target") | a change wraps a UIKit view (`UIViewRepresentable`, the maps) or touches a `Package.swift`, an Xcode target's concurrency or isolation settings |
| `build-and-schemes.md` ("Build integration", "Build configurations and schemes") | a change touches the Xcode project, a scheme, a build phase, the XCFramework build, `xcodebuild` flags or a build configuration |
| `swiftlint.md` ("SwiftLint") | a SwiftLint step fails, or a change touches `iosApp/.swiftlint.yml` or adds a `swiftlint:disable` |


## Architecture

- One local Swift Package per feature under `iosApp/Packages/<Feature>/` (`History`,
  `Route`, `Tracking`), mirroring `androidApp/feature-*`. Copy an existing `Package.swift`
  (`swift-tools-version: 5.9`, `defaultLocalization: "en"`, `platforms: [.iOS("26.5")]`, the app's deployment target (`.v17` and the other named values stop far below it; the string form is accepted by tools-version 5.9), one library product, one target with `resources: [.process("Localizable.xcstrings")]`)
  rather than hand-rolling one.
- Every feature package depends on `SharedKit`, never on `TrailMetricsShared.xcframework`
  directly. `SharedKit` is just `@_exported import TrailMetricsShared`, so Swift files
  `import SharedKit` — never `import TrailMetricsShared`.
- `DesignSystem` already exists (`Color.trailGreen`, `.trailRed`, ...). SwiftUI components used by 2+ features go there; don't
  create a second shared UI package.
- Feature packages do not depend on each other. Cross-feature navigation is wired in the
  app target (`iosApp/TrailMetrics/ContentView.swift`), not inside a feature.
- The dependency direction is view to ViewModel to `domain` (through `SharedKit`) to nothing. A
  ViewModel holds presentation state only: no file, database or HTTP access of its own and no
  formatting or business rule that belongs in `domain` (`tm-kmp-shared`, "Where logic lives").
  Enforced: reviewer only. Violation: `blocking` for data access, `important` for a misplaced rule.
- A ViewModel takes its dependencies in `init`, typed to the Kotlin interface
  (`ActivityHistoryRepository`), never to a `data` class. Enforced: reviewer only. Violation:
  `blocking`.
- One reason to change per type. Enforced: SwiftLint `type_body_length` (300), `function_body_length`
  (60) and `cyclomatic_complexity` (15) are the mechanical signal; a type that mixes state, IO and
  formatting is the judgement one, reviewer only. Violation: `important`.
- Never an `as?`/`is` cast on an abstraction to reach a concrete type (decoding a bridged Kotlin
  exception, as `RouteViewModel`'s `underlyingRouteError` does, is the one exception). Enforced:
  reviewer only. Violation: `important`.
- Crashes, ANR, exceptions, actors, scene phase, leaks and performance: `tm-robustness`.
- The third-party dependencies are `ios-maps-sdk` (GoogleMaps) in the feature packages that
  render maps, and `firebase-ios-sdk` (the `FirebaseCrashlytics` product) on the app target, imported in
  `iosApp/TrailMetrics/CrashReporting/CrashReporting.swift` alone: the rest of the app and `shared` know the
  Kotlin interface `FatalKotlinExceptionReporter`, not Firebase. A Release build starts crash reporting when
  the owner's `GoogleService-Info.plist` (git-ignored) is in `iosApp/TrailMetrics/`; a Debug or Debug-UITest
  build also needs the launch argument `CrashReporting.debugOptInArgument` (`-crashReportingInDebug`, a local
  scheme change for a manual check); the gate and CI build without the plist.
- Privacy manifests: `iosApp/TrailMetrics/PrivacyInfo.xcprivacy` (app, also covering the Kotlin
  framework linked into it; crash data and other diagnostic data for Crashlytics, as Crashlytics' own manifest
  declares them) and `iosApp/TrackingWidget/PrivacyInfo.xcprivacy` (the widget, which links no
  required-reason API). The Google Maps SDK and each Firebase library ship their own. New code that uses a required-reason API
  (user defaults, file timestamps, boot time, disk space, active keyboards) adds its entry in the same
  change; fetch Apple's current list of categories and reason codes then, it is not stored here.
- `iosApp/TrackingWidget/` is the Live Activity widget extension. It is a separate target,
  but SwiftLint and the iOS build still cover it.

## ViewModel shape

```swift
@MainActor
public class HistoryViewModel: ObservableObject {
    @Published public var activities: [ActivityRecord] = []
    @Published public var isLoading = true
    @Published public private(set) var errorMessage: String?

    private let activityHistoryRepository: ActivityHistoryRepository
    private let observeActivitiesUseCase: ObserveActivitiesUseCase

    public init(
        activityHistoryRepository: ActivityHistoryRepository = KoinHelper().getActivityHistoryRepository(),
        observeActivitiesUseCase: ObserveActivitiesUseCase = KoinHelper().observeActivitiesUseCase()
    ) {
        self.activityHistoryRepository = activityHistoryRepository
        self.observeActivitiesUseCase = observeActivitiesUseCase
    }

    public func observe() async {
        for await update in observeActivitiesUseCase.invoke() {
            await MainActor.run {
                switch onEnum(of: update) {
                case .loaded(let loaded):
                    activities = loaded.activities
                case .failed:
                    errorMessage = HistoryErrorMessage.general
                }
                isLoading = false
            }
        }
    }

    public func onErrorDismissed() {
        errorMessage = nil
    }
}
```

Never iterate a repository `Flow` directly from Swift: SKIE terminates the app when the Flow
fails, so observe through a use case that turns the failure into a value on the Kotlin side
(here `ObserveActivitiesUseCase`, which emits `Failed`).

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
  Between two streams nobody consumes (before the first `.task` runs, so a failed load
  started in `init`, and while the screen is covered), and `yield` to a missing or terminated
  continuation loses the event. So `emit` keeps every event that `yield` does not report as
  `.enqueued` in `pendingEvents` (at most `maxPendingEvents`, 10, oldest dropped first), and
  `makeEventsStream()` yields those to the new stream first (see `RouteViewModel.emit`;
  `TrackingViewModel` keeps the same mechanism in `TrackingEventChannel`, whose new stream also
  re-offers `.sessionNotSaved` while the warning is still raised).
- iOS is **not** part of the Android MVI migration. iOS ViewModels expose intent methods
  (`onGenerateRouteClicked()`, `onMapTapped(_:)`). Keep that style. Some existing methods
  take completion closures (`TrackingViewModel.onFinishClicked(snapshotFilePath:onSaved:)`,
  `DetailsViewModel.onDeleteConfirmed(onDeleted:)`). For new code, prefer a `UiEvent` case,
  but don't rewrite existing closures unless the task asks for it.
- Known limitation, deliberately not fixed: `TrackingViewModel.onStopClicked` cancels the
  observation tasks that only `init` starts, so an instance does not observe again after Stop; no
  user path reaches it (every Stop dismisses the screen or swaps in `finishCard`).

## Koin / KoinHelper

- `TrailMetricsApp.init()` is the only place that calls `KoinInitIosKt.doInitKoinIos()`.
  Never call it from a View's `init` (SwiftUI can re-run it, starting Koin twice and crashing).
  In the `Debug-UITest` build only (`#if UITEST_SEAM`), a `-uiTestScenario <name>` launch
  argument makes it call `doInitKoinIosForUiTest(scenario:)` instead (the UI-test seam of the
  test-only framework variant; files in `iosApp/TrailMetrics/UITestSupport/`, all under the same
  condition). See `tm-testing`, "XCUITest" (`xcuitest-rules.md`).
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
- Never drop an error: no `try?` (rules and the one exception: "SwiftLint", `swiftlint.md`, `optional_try`) and
  no unstructured `Task { try ... }` without `do/catch` (review only). A caught error reaches the
  user through the ViewModel's `.showError` event, and state stays as it was. Only Kotlin
  functions with `@Throws` can throw into Swift without crashing; see `tm-kmp-shared` ("`@Throws`
  policy", `swift-interop.md`). History and Details have no events stream: they publish `errorMessage` and show it
  in an "Error" alert.
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
- No `accessibilityIdentifier` for UI tests where text finds the element; only where it cannot
  (image-only buttons, rows, changing labels), named `<screen>.<element>` (`tm-testing`, "XCUITest", `xcuitest-rules.md`).
- Add a `#Preview` for new screens and reusable components. Today `ContentView` and
  `RouteMapUnavailableView` are the two files with one: the feature screens build a ViewModel that resolves from
  `KoinHelper()`, and `TrailMetricsApp.init()` is what starts Koin. The fakes (`TestSupport`) are linked from test
  targets only, so a preview in `Sources/` cannot see them. Until that is decided, a preview is of
  a view that takes plain values and closures (a row, a card, a metric cell); do not link
  `TestSupport` from a `Sources/` target and do not start Koin in a preview. Open proposal, not a
  rule: a small `#if DEBUG` preview-fakes file in the package that owns the screen, hand-written
  against the Kotlin interfaces, which keeps `TestSupport` out of the app.

## Naming (Swift)

- Types `PascalCase`, functions/properties `camelCase`. No `I` prefix and booleans read as
  questions, as in `tm-android` ("Naming (Kotlin)", `kotlin-conventions.md`).
- SPM packages and Swift modules are `PascalCase` single words (`History`, `DesignSystem`).
  The Kotlin "lowercase, no underscores" rule applies to Kotlin packages and Gradle modules;
  the Swift form of it is: no underscores or hyphens in package names.
- Per-feature types: `<Feature>View`, `<Feature>ViewModel`, `<Feature>UiEvent`.
  Extension files: `Type+Purpose.swift` (`RouteUiError+Message.swift`,
  `Color+TrailMetrics.swift`).
- Identifiers are at least 3 characters (`id` is the one exception, enforced by
  `identifier_name`), so no `vm`, `i` or `e`.
- Test functions: `func test_savesActivity_recalculatesCalories()`, never `test1`.

## No deprecated APIs (Swift)

`CLAUDE.md` states the rule; the Swift specifics:
- Never call anything marked `@available(*, deprecated)`, or anything deprecated at or below
  the iOS 26.5 deployment target. Xcode reports these only as warnings, and SwiftLint doesn't
  catch them, so read the build log. Examples that matter here: `NavigationView` →
  `NavigationStack`; single-parameter `.onChange(of:perform:)` → the two-parameter
  `.onChange(of:) { oldValue, newValue in }` form already used in `TrackingView`;
  `NavigationLink(isActive:)` → `navigationDestination`.
- Fix the call rather than silencing it. Swift has no narrow call-site suppression: marking
  your wrapper `@available(*, deprecated)` only moves the warning to its callers. If a
  deprecation is genuinely unavoidable, stop and report it instead of wrapping it.
- Own APIs: same rule as Kotlin (`tm-android`, "No deprecated APIs (Kotlin)", `kotlin-conventions.md`), with
  `@available(*, deprecated)`.

## No dead code

- Otherwise as `tm-android` ("No dead code", `kotlin-conventions.md`): no commented-out code, no unused declarations.
- No unused imports. Enforced: reviewer only (no SwiftLint rule runs; "SwiftLint" says why). Import `SharedKit`, not
  `TrailMetricsShared`.

## Known deviations in the current code

Don't copy these as a pattern for new code.
- None today.
