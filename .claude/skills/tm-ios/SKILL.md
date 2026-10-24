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
  (`swift-tools-version: 5.9`, `defaultLocalization: "en"`, `platforms: [.iOS(.v17)]`, one library product, one target with `resources: [.process("Localizable.xcstrings")]`)
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
- The only third-party dependency is `ios-maps-sdk` (GoogleMaps) in feature packages that
  render maps.
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
  `TrackingViewModel.emit` is the same).
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
  condition). See `tm-testing`, "XCUITest".
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
- Never drop an error: no `try?` (rules and the one exception: "SwiftLint", `optional_try`) and
  no unstructured `Task { try ... }` without `do/catch` (review only). A caught error reaches the
  user through the ViewModel's `.showError` event, and state stays as it was. Only Kotlin
  functions with `@Throws` can throw into Swift without crashing; see `tm-kmp-shared` ("`@Throws`
  policy"). History and Details have no events stream: they publish `errorMessage` and show it
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
  (image-only buttons, rows, changing labels), named `<screen>.<element>` (`tm-testing`, "XCUITest").
- Add a `#Preview` for new screens and reusable components. Use the ViewModel's
  default-parameter `init` to inject fakes where a live Koin graph isn't available.

## Strings

No user-visible text is a hardcoded string. Every text the user reads (labels, button titles,
navigation and tab titles, alerts, empty and error states, accessibility labels and hints, map
marker titles) comes from a String Catalog, `Localizable.xcstrings`, next to the sources of the
package that shows it (`iosApp/Packages/<Feature>/Sources/<Feature>/`), of the app target
(`iosApp/TrailMetrics/`) or of the widget extension (`iosApp/TrackingWidget/`). Language: English
only for now (`defaultLocalization: "en"`); adding one means adding its column to the catalogs,
no code change.

- **Bundle.** Inside an SPM package SwiftUI looks in the main bundle unless told otherwise, so a
  literal without the package bundle is silently not localized. Only `Text` takes `bundle:`;
  every other view takes its text as a `Text`:

  ```swift
  Text("Generate Route", bundle: .module)
  Button { save() } label: { Text("Save", bundle: .module) }
  Label { Text("Reset", bundle: .module) } icon: { Image(systemName: "arrow.clockwise") }
  TextField(text: $weightInput) { Text("Weight (kg)", bundle: .module) }
  .navigationTitle(Text("User Profile", bundle: .module))
  .alert(Text("Error", bundle: .module), isPresented: $isShown) { ... }
  ```

  In the app and widget targets the bundle is the main one: `bundle: .main`.
- **Outside a View** (ViewModel, error and formatter texts, `GMSMarker.title`) a `String` shown
  with `Text(string)` is verbatim and never localized, so make the string with
  `String(localized: "key", bundle: .module)`. Use a computed property, not a `static let`, so it
  follows the language at the time it is read. A child view that shows a label takes a `Text`
  (`HistoryMetricCell(label: Text("metric_distance", bundle: .module), ...)`), not a `String`.
  The Live Activity's `activityType` stays an English identifier that the widget localizes with
  its own catalog (`Text(LocalizedStringKey(activityType), bundle: .main)`).
- **Keys.** The English text is the key (`Text("Generate Route", ...)`). A text used in several
  places of a package, or one that is formatted, gets a descriptive snake_case key
  (`delete_activity_title`, `general_error_message`) whose English value is in the catalog.
  Interpolated texts use format arguments in the key, never `+`. A new key is added to the
  catalog in the same change, with an `en` string unit.
- **Not user-visible text, leave as is:** `accessibilityIdentifier`, log messages, `systemName:`
  symbols, URL schemes and notification names, test code and fakes, `UITestSupport`, previews'
  sample data.
- **Enforced** by two SwiftLint custom rules in `iosApp/.swiftlint.yml` (see "SwiftLint"):
  `localized_text_without_bundle` (a `Text("literal")` without `bundle:`) and
  `literal_text_in_view_initializer` (a string literal as the first argument of `Button`, `Label`,
  `TextField`, `.navigationTitle`, `.alert`, `.accessibilityLabel` and similar). Both cover
  production sources of the packages, the app target and the widget only. They cannot see a
  `String` that is shown later (`Text(message)`), so review checks that those strings are made
  with `String(localized:bundle:)` (`tm-pr-review`). Self-test of the rules:
  `scripts/check-localized-strings.sh --self-test` (in the gate's iOS steps).
- A package's tests resolve one of its keys through `Bundle.module` with
  `LocalizationAssertions.assertResolves` (TestSupport); copy `HistoryTests/LocalizationTests.swift`
  for a new package (it needs `@testable import`).
- Known limits, not fixed here: the texts that `MetricsFormatter` (Kotlin) returns, with their
  unit words, and the widget's own number formatting are hardcoded (board:
  `shared-metrics-formatter-user-visible-strings`, `ios-hardcoded-number-formatting`).

## Build integration (XCFramework pre-action + Run Script)

- `scripts/build-kmp-framework.sh` is the one place that decides whether the shared
  XCFramework needs Gradle. It hashes the **content** of every `*.kt`/`*.kts` under
  `domain/src data/src core/src shared/src shared-uitest/src`, plus `settings.gradle.kts`, the root
  `build.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml`,
  `gradle/wrapper/gradle-wrapper.properties`, `domain|data|core|shared|shared-uitest/build.gradle.kts` and
  `local.properties` (if present; BuildKonfig compiles its API key into the framework). It
  compares the variant and that hash against `shared/build/.xcode_kmp_stamp` and runs
  `./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework` when the hash or the variant
  changed or the XCFramework is missing. With `--variant uitest` it also builds the test-only
  variant of `shared-uitest`, checks its API against production's (`scripts/check-variant-api.sh`)
  and copies it over the same
  debug path (ADR-002, "Amendment"). The stamp is deleted before Gradle and written only after
  it succeeds. `SharedKit/Package.swift` points at the **debug** XCFramework output.
  Deliberately not hashed: `gradlew`, `gradle/wrapper/gradle-wrapper.jar` and
  `gradle/gradle-daemon-jvm.properties`. `gradle-wrapper.properties` names the Gradle version;
  the first two only launch that version and the third only selects the JVM that runs the
  Gradle daemon, so none of them is expected to change the Kotlin/Native output. The gate's iOS
  filter (`IOS_PATHS`) still lists all three, so its iOS steps run when the build tooling
  changes. On a machine whose stamp matches, a diff of only these files makes the gate's
  "KMP XCFramework" step print "up to date" and skip Gradle. That is intended; if a change to
  one of them ever does change the framework, delete the stamp to force the rebuild.
- Callers:
  - The shared `TrailMetrics` scheme
    (`TrailMetrics.xcodeproj/xcshareddata/xcschemes/TrailMetrics.xcscheme`) runs it as a
    Build pre-action. That is what makes a single build pick up a Kotlin change: Xcode copies
    the XCFramework (`ProcessXCFramework`) and compiles the Swift packages *before* any of
    the app target's phases run. The pre-action output, including Gradle errors, is in the
    build log, and a failing pre-action fails the build.
  - The shared `TrailMetricsUITests` scheme has the same Build pre-action (see "Build
    configurations and schemes").
  - The `TrailMetrics` target's "Build KMP Shared Framework" Run Script phase (first phase,
    `alwaysOutOfDate = 1`, output `.xcode_kmp_stamp`) runs it with `--build-phase` as a
    safety net. If the pre-action didn't run, it rebuilds and then fails the build with
    "build again" rather than link the stale copy. Don't declare the XCFramework as a phase
    output: Xcode reports "Cycle inside TrailMetrics".
  - `scripts/pre-push-check.sh` runs it before the iOS build, then
    `scripts/check-production-framework.sh` on the production framework, and runs it with
    `--variant uitest` right before the package tests (see below).
  - CI's `ios-main` job runs it in its "Build KMP Shared Framework" step, before the iOS
    simulator tests and the `xcodebuild` build, runs `scripts/check-production-framework.sh`
    after it, and builds the variant in the step "Build test-only framework variant" before
    "Run iOS package tests"; `ios-build-ui` runs `scripts/build-kmp-framework.sh --variant uitest`.
- The Swift package tests link the **test-only variant**, not production: the Kotlin test
  support they need (`SwiftTestFlow`, `SwiftFailingTestFlow`, `SwiftTestScope`, `SwiftTestResult`,
  package `dev.roozbahani.trailmetrics.uitest.testsupport`) is in `shared-uitest`. The production
  framework contains none of it; `scripts/check-production-framework.sh` (gate and `ios-main`)
  fails when any of those names, or the `testsupport` package name, is in its binary. The
  variant's API check (`scripts/check-variant-api.sh`) lists these four classes with the UI-test
  seam as the only names allowed in the variant alone.
- A per-user `xcuserdata/.../TrailMetrics.xcscheme` with the same name shadows the shared
  scheme and has no pre-action. If every Kotlin change ends in the "build again" error,
  delete the per-user copy.
- `xcodebuild test` inside a package directory (`iosApp/Packages/<Name>`) uses the package's
  own scheme. It runs neither the pre-action nor the phase, so run
  `scripts/build-kmp-framework.sh --variant uitest` first (the gate does): the package tests
  need the test-only variant. A normal build afterwards rebuilds production.
- Building the app from the command line (the command is CI's `ios-main` "Build iOS app"
  step; the gate runs the same one):

  ```bash
  cd iosApp
  xcodebuild build -project TrailMetrics.xcodeproj -scheme TrailMetrics \
    -destination "generic/platform=iOS Simulator" -skipMacroValidation \
    ARCHS=arm64 EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO
  ```

  Without the architecture flags a build on clean derived data fails (the XCFramework has no
  x86_64 slice). The gate also pipes the output through `scripts/filter-xcode-log.sh`, which
  hides the exported build settings (they include the Maps key) from the log.
- Never disable, reorder or bypass the pre-action or the phase, and keep the shell logic in
  the script, not inline in the scheme or the project file.
- Unexpected "missing/stale symbol from `TrailMetricsShared`": look in the build log for the
  "Build KMP Shared Framework" pre-action and phase lines
  ("rebuilding shared framework..." / "up to date, skipping Gradle build"). Deleting the stamp
  forces the next build to run Gradle.
- `./gradlew clean` wipes the XCFramework; the next Xcode build has to regenerate it.

## Build configurations and schemes

- The project has three build configurations: `Debug`, `Release` and `Debug-UITest`.
  `Debug-UITest` is a copy of `Debug` in every configuration list (the project, `TrailMetrics`,
  `TrackingWidgetExtension`, `TrailMetricsUITests`); the only difference is at the project level,
  where `SWIFT_ACTIVE_COMPILATION_CONDITIONS` is `DEBUG UITEST_SEAM $(inherited)`. So the project's
  targets see `UITEST_SEAM` and `DEBUG`; the Swift packages see `DEBUG` only. A build setting
  added to or changed in `Debug` belongs in `Debug-UITest` too.
- Keep `Debug` in the name of a configuration that should build like Debug: Xcode picks the
  SwiftPM packages' debug or release build from the name (seen with `xcodebuild`: a
  configuration named `UITest` built the packages as Release, `-O`, whole-module, no `DEBUG`).
- Two shared schemes build the app:
  - `TrailMetrics`, the normal scheme: Run, Test and Analyze on `Debug`, Profile and Archive on
    `Release`, and no testables. It links the production framework. CI's "Build iOS app" step
    and the gate build it.
  - `TrailMetricsUITests`, the UI-test scheme: the same Build pre-action, Test and Launch on
    `Debug-UITest`, the `TrailMetricsUITests` testables and that target's build-for-testing
    entry. It links the test-only variant of the framework (built by `shared-uitest`, ADR-002
    "Amendment").
- How the variant is picked: `scripts/build-kmp-framework.sh` builds the variant when Xcode's
  `CONFIGURATION` is `Debug-UITest` (the pre-action and the `--build-phase` safety net alike),
  and with `--variant uitest` when it is called outside Xcode; otherwise it builds production.
  Both go to the same debug path, which `SharedKit/Package.swift` links in every configuration.
- Running the UI tests locally (a concrete simulator; the pre-action builds the variant):

  ```bash
  cd iosApp
  xcodebuild test -project TrailMetrics.xcodeproj -scheme TrailMetricsUITests \
    -destination "platform=iOS Simulator,id=<simulator id>" -skipMacroValidation \
    ARCHS=arm64 EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
    2>&1 | ../scripts/filter-xcode-log.sh
  ```

  Add `-only-testing:TrailMetricsUITests/<TestClass>` for one class. Without the architecture
  flags a build on clean derived data fails (the XCFramework has no x86_64 slice). The filter
  hides the exported build settings, which carry the Maps key, from the log.
- After a UI-test run the debug path holds the variant until the next normal build. That build
  rebuilds production on its own: the stamp records the variant, so its pre-action prints
  "KMP source or framework variant changed, rebuilding shared framework (production)..." and
  replaces the variant before anything links it.

## Naming (Swift)

- Types `PascalCase`, functions/properties `camelCase`. No `I` prefix and booleans read as
  questions, as in `tm-android` ("Naming (Kotlin)").
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
  the iOS 17 deployment target. Xcode reports these only as warnings, and SwiftLint doesn't
  catch them, so read the build log. Examples that matter here: `NavigationView` →
  `NavigationStack`; single-parameter `.onChange(of:perform:)` → the two-parameter
  `.onChange(of:) { oldValue, newValue in }` form already used in `TrackingView`;
  `NavigationLink(isActive:)` → `navigationDestination`.
- Fix the call rather than silencing it. Swift has no narrow call-site suppression: marking
  your wrapper `@available(*, deprecated)` only moves the warning to its callers. If a
  deprecation is genuinely unavoidable, stop and report it instead of wrapping it.
- Own APIs: same rule as Kotlin (`tm-android`, "No deprecated APIs (Kotlin)"), with
  `@available(*, deprecated)`.

## No dead code

- Otherwise as `tm-android` ("No dead code"): no commented-out code, no unused declarations.
- No unused imports (`unused_import` is enabled). Import `SharedKit`, not
  `TrailMetricsShared`.

## SwiftLint (CI-enforced, `--strict`)

Config: `iosApp/.swiftlint.yml`. Run it from `iosApp/` with `swiftlint lint --strict`. It
runs in `scripts/pre-push-check.sh` (whenever a file other than markdown under `iosApp/`,
`domain/`, `data/`, `core/`, `shared/` or `shared-uitest/` changed, or a root Gradle file: `build.gradle.kts`,
`settings.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml`, or a file that runs the
Gradle build: `gradlew`, `gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties`,
`gradle/gradle-daemon-jvm.properties`, or `scripts/build-kmp-framework.sh`) and in the CI macOS job, followed by an `xcodebuild` simulator build.

- `--strict` promotes every warning to a failure. The `warning` thresholds are the real
  limits: line length 120, function body 60 lines, type body 300 lines, cyclomatic
  complexity 15.
- `force_unwrapping`, `force_cast` and `force_try` are errors. Restructure with
  `guard let`/`if let`, `as?` with explicit `else` handling, or `do`/`catch`.
- Opt-in rules on top of the defaults: `force_unwrapping`, `unused_import`, `explicit_init`,
  `closure_spacing`, `empty_count` (use `.isEmpty`), `fatal_error_message`.
- Custom rule `optional_try` (error): a regex for `try?`, not matched inside comments and
  string literals (`excluded_match_kinds`); `try` and `try!` are not its business (`force_try`
  covers `try!`). Handle the error with `do`/`catch`; a deliberate `try?` needs the
  `swiftlint:disable:next optional_try - <reason>` comment on the line above, allowed only for a
  best-effort side effect whose failure the user can't act on, the reason saying why the error can
  be dropped there. The only two in production code are `deleteSnapshotFile` (an orphaned image
  file after the record is gone) and `TrackingLiveActivityController`'s `Activity.request` (Live
  Activities can be turned off); the test helpers `waitUntil` (TestSupport) and
  `SnapshotFileFixture.remove` (HistoryTests) carry the same comment; no other `try?` is left
  under `iosApp/`. SwiftLint does not check that a reason is there or true: review does. An invalid `excluded_match_kinds` name only prints "Invalid configuration for
  'optional_try' rule" and turns the rule off, without failing `--strict`; `scripts/check-optional-try.sh --self-test`
  (in the gate's iOS steps and CI's `ios-main`) lints fixtures with the committed config, fails on that message,
  and shows the rule silently off on a config with an unknown kind.
- Custom rules `localized_text_without_bundle` and `literal_text_in_view_initializer` (error):
  see "Strings". They match source text with `included`/`excluded` path regexes, so a new
  production source folder outside `Packages/*/Sources`, the files directly in `iosApp/TrailMetrics/`
  and `iosApp/TrackingWidget/` needs its path added to both rules.
- Don't add `// swiftlint:disable` comments and don't edit `.swiftlint.yml` to make a
  violation pass. Refactor instead, or ask if the rule genuinely doesn't fit. A suppression
  needs explicit human approval and a stated reason. Every existing one has the form
  `// swiftlint:disable:next <rule> - <reason>`.

## Known deviations in the current code

Don't copy these as a pattern for new code.
- `TrackingViewModel` extracts the metrics from `TrackingState` and recomputes calories itself, the same
  rules Android's `TrackingViewModel` holds (`tm-kmp-shared`, "Where logic lives";
  `tracking-metrics-calories-to-domain`).
