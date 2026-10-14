# Epic: iOS UI tests (XCUITest) for double taps, stale results and the delete error

- **Slug:** ios-ui-tests
- **Status:** first approved with #138 (S0 results in #139, UI-test target in #140). Rewritten
  on 2026-10-13 around a test-only XCFramework variant after the human decided that the UI-test
  fakes must not be part of the production `TrailMetricsShared.xcframework` (Q1, answered
  again); PR #141 (the fakes inside the production framework) was closed unmerged for that
  reason. Approved again when the PR with this text merges.
- **Source:** BOARD.md record `test-ios-ui-double-tap-and-stale-results` (Order 100), and item (1)
  of the `agentic-dev-loop` record's Done when (the iOS half of "a deterministic test seam and
  UI-test targets ... a fast smoke subset in the local gate ... the full UI suite in CI").
- **Integration branch:** none (Q7). A chain of PRs against `main`, each leaving `main` green
  and the app unchanged for users: every subtask adds test infrastructure or a test, never half
  a feature.
- **Goal:** `xcodebuild test -scheme TrailMetricsUITests` runs an XCUITest target against the
  real app, built in the `Debug-UITest` configuration against a test-only variant of the shared
  framework and launched with deterministic fakes for location, directions, user profile,
  history storage and the tracking launcher. Five scenarios prove what today only ViewModel
  unit tests prove: Finish tapped twice saves one History entry; Generate then Reset leaves no
  route; Generate tapped twice sends one directions request; the delete confirmation given
  twice deletes once; a failed delete shows the "Error" alert. CI's iOS job runs the suite; the
  local gate runs one smoke scenario when the diff touches iOS UI or ViewModel code. Normal
  Debug and Release builds contain no seam code, Kotlin or Swift.
- **Out of scope:** Android (done: the Compose UI tests of `feature-history`, `feature-route`,
  `feature-tracking`); any user-visible behavior change; the map's drawn content (polylines,
  markers); real GPS, permission dialogs, the Live Activity, notifications (they stay on the
  `agentic-dev-loop` manual device list); new third-party dependencies; Release-build tooling for
  the shared XCFramework (board record `release-build-links-debug-xcframework`); moving
  `SwiftTestSupport.kt` out of the production framework (board record
  `swift-test-support-ships-in-production-framework`).
- **Approved by:** Ali Roozbahani, by merging the PR that contains this text (2026-10-13)

Evidence, by source:
- **Plan (#138):** the files on `main` at `42dc442` and read-only commands run on 2026-10-12
  (Xcode 27.0, Swift 6.4, one local simulator runtime: iOS 26.5).
- **S0 spike** (2026-10-13, Xcode 27.0, recorded in #139): marked "S0 spike" where used.
- **S1a spike** (2026-10-13, Xcode 27.0, Apple M4, local worktree, nothing pushed): findings
  F11 to F22, marked "S1a spike, reported by the spike run, not re-run by this PR". The PR that
  rewrote this plan around them is docs only and built nothing.

Every claim is marked **verified** (read in a file or seen in a command's output) or **not
verified** (a belief that a subtask must check).

## Findings

**F1. App and composition root (verified).** `TrailMetricsApp.init()` calls
`KoinInitIosKt.doInitKoinIos()`, then configures the Maps SDK through
`RouteMapConfiguration.configure(apiKey:)` only when the key read from Info.plist is not empty.
`doInitKoinIos()` calls `initKoin()`, which `startKoin`s `commonModule`,
`commonTrackingModule`, `databaseModule`, `networkModule`, `useCaseModule`,
`userProfileModule`, `activityHistoryModule`, `directionsModule` and the iOS
`platformModules` (`iosCommonModule`, `iosLocationModule`). There is no launch argument, no
environment read and no override hook today.

**F2. What the five scenarios need from Koin (verified).** Bindings the fakes must replace:
`LocationRepository` (`IosLocationRepositoryImpl`, single, also used directly by
`IosTrackingServiceLauncher`, which turns on background location updates);
`TrackingServiceLauncher`; `DirectionsRepository` (`DirectionsRepositoryImpl` over Ktor,
reached through `GenerateClosedRouteUseCase`; `KoinHelper` has no getter for the repository
itself); `ActivityHistoryRepository` (Room through `ActivityDao`); `UserProfileRepository`
(`KeyValueStorage`). The Views get their ViewModels from default-parameter `init`s resolving
`KoinHelper()` (`RouteView` builds `RouteViewModel()`, `TrackingView` and `DetailsView` build
theirs in `init`), so a Koin override reaches every screen without touching a View. Koin is
4.2.2 (`koinBom`). **Verified** (S0 spike, 2026-10-13, Xcode 27.0): in Koin 4.2.2 a later
module overrides a binding by default, no `allowOverride` needed. `initKoin { }` runs its
appDeclaration BEFORE the production modules, so anything passed through it is replaced by
the production modules (a throwaway `iosTest` case got the real `UserProfileRepositoryImpl`
back). `initKoin()` followed by `loadKoinModules(overrideModule)` returns the fake, and an
overridden single (and the Room database, when `ActivityHistoryRepository` is overridden) is
never constructed.

**F3. Existing Swift fakes do not fit the app (verified).** `TestSupport`
(`FakeLocationRepository`, `FakeActivityHistoryRepository`, `FakeUserProfileRepository`) and
`Route/Tests/.../FakeDirectionsRepository` are written for unit tests: `observeActivities()`
emits a fixed list and does not reflect saves or deletes (a History screen would never show a
new entry), Swift cannot emit into a Kotlin `Flow`, and `TestSupport/Package.swift` says the
product is linked only from `.testTarget`s, never from a Sources target. Their scripting ideas
(hold a call until released, count calls, fail on demand) carry over.

**F4. Kotlin test support already ships in the production XCFramework (verified).**
`shared/src/iosMain/.../testsupport/SwiftTestSupport.kt` is "TEST SUPPORT ONLY" and is compiled
into the framework because the Swift package tests link that framework and a second Kotlin
framework cannot share its types. `SharedKit/Package.swift` points at the **debug** XCFramework
for every build configuration, so a Release app links it too. This is a pre-existing issue,
separate from this epic: the UI-test fakes do not join it (D1, F19), and moving
`SwiftTestSupport.kt` out is out of scope (board record
`swift-test-support-ships-in-production-framework`).

**F5. Xcode project (verified).** `xcodebuild -list`: targets `TrailMetrics` and
`TrackingWidgetExtension`; configurations Debug and Release; schemes include the shared
`TrailMetrics`. `project.pbxproj` has `objectVersion = 77` and uses
`PBXFileSystemSynchronizedRootGroup`s for `TrailMetrics/` and `TrackingWidget/`: a new file in
those folders joins its target without a project-file edit, and a new target needs one new
synchronized group plus the target, its build configurations, a target dependency and a
product reference. The project-level deployment target is iOS 26.5. The shared scheme has a
Build pre-action (`scripts/build-kmp-framework.sh`) and one BuildActionEntry (the app). Debug
defines `DEBUG` in `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. **Verified** (S0 spike, 2026-10-13,
Xcode 27.0): the hand edit of the UI-test target lists `TrailMetricsUITests` in `xcodebuild
-list`, the CI "Build iOS app" command still succeeds, the build-for-testing-only entry is not
part of `xcodebuild build`, and Xcode generated no other changes. Since #140 the target
`TrailMetricsUITests` (synchronized group, `LaunchUITests`) exists, and the `TrailMetrics`
scheme has its build-for-testing-only entry and its Testables entry; D2 moves both to a
dedicated scheme. **Not verified:** the project edits under Xcode 26.6, which CI uses; the
first check is each project PR's own CI run.

**F6. What XCUITest can reach in the Views (verified from the source; at runtime the Route
screen and the map long press are verified in S0, the History seed in S1a, the other screens
not yet).**
- Route: Generate is a `Button` whose label switches between the text "Generate Route" and a
  `ProgressView` while loading, and it is `.disabled(!canGenerateRoute)`
  (`canGenerateRoute` needs a start point, at least 3 waypoints and not loading). The top-bar
  Reset and the profile button are image-only. The `StartTrackingPanel` (text buttons "Reset"
  and "Start Tracking") is shown only while a generated route and a start point exist.
- Waypoints are added only by a **long press on the `GMSMapView`**
  (`RouteMapView.Coordinator.mapView(_:didLongPressAt:)`). Every Route and Tracking scenario
  therefore needs XCUITest to long-press the map and the Maps SDK to report it. **Verified**
  (S0 spike, 2026-10-13, Xcode 27.0, CI placeholder key): `press(forDuration:)` of 1 s or more
  at normalized points (about y 0.4 to 0.6) on the window coordinate, on the map element or on
  an element with identifier `route.map` adds a waypoint; after 3 presses "Generate Route"
  becomes enabled. A 0.3 s press does not register (negative control). The map is an `Other`
  element of class GMSMapView without an identifier. A SwiftUI `.accessibilityIdentifier` on
  `RouteMapView` gives an element that covers the whole screen (tab bar included), so presses
  stay inside the map area.
- The top-bar Reset already exposes identifier `arrow.clockwise` and label "Refresh" through
  SwiftUI's SF Symbol default (verified, S0 spike, 2026-10-13, Xcode 27.0).
- Tracking: "Start", "Finish" are text-labelled. Finish appears only after
  `isRouteCompleted` (tracking state, last location within 25 m of the last planned point,
  progress index near the end). Finish writes a snapshot request that `TrackingMapView`
  answers, then calls `onFinishClicked(snapshotFilePath:onSaved:)`; `onSaved` dismisses.
- History rows are `Button`s in a `LazyVStack` (no identifier). Details' Back and Delete
  (trash) are image-only buttons; the confirmation is an `.alert("Delete this activity?")`
  with a "Delete" button; the failure is an `.alert("Error")` with the message
  `HistoryErrorMessage.general` and an "OK" button.
- Map content inside `GMSMapView` is not asserted by any scenario.

**F7. CI iOS job (verified, `.github/workflows/ci.yml` and `gh run view`).** Runner image
(S0 spike, 2026-10-13, Xcode 27.0, from the actions/runner-images documentation and the last
full CI run's log): `macos-latest` is
`macos-26-arm64`, version `20260907.0351.1`, default Xcode 26.6, simulator runtimes iOS 26.2,
26.4 and 26.5; the last full CI run built with Xcode 26.6 and ran the package tests on an
iPhone 17 iOS 26.5 simulator, so the deployment target 26.5 is met. Steps after
"Classify changes", all skipped on `decision == 'light'`: "Select Xcode", "Install SwiftLint",
"Run SwiftLint", JDK, Gradle, "Build KMP
Shared Framework", "Run iOS simulator tests" (Gradle), "Generate" the secrets config with a CI
placeholder key, "Build iOS app" (`xcodebuild build`, `generic/platform=iOS Simulator`, with
`ARCHS=arm64 EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO`),
"Run iOS package tests" (concrete simulator: the last available iPhone from
`xcrun simctl list devices available iPhone`). `timeout-minutes: 40`. The last six runs took
4.5 min (light) and 11.5 to 16 min (full); in a full run of 13.5 min the framework build took
3.6 min, the app build 1.3 min and the package tests 7.1 min. `actions/upload-artifact@v7` is
already used in the android job.

**F8. Local gate (verified, `scripts/pre-push-check.sh`).** When the iOS scope block sets
`TOUCHES_IOS_OR_SHARED` (regex `IOS_PATHS`: `iosApp/`, `domain/`, `data/`, `core/`,
`shared/`, root Gradle files, `scripts/build-kmp-framework.sh`; `*.md` excluded) and the
classification is `full`, it runs SwiftLint, the framework build, the generic `xcodebuild
build` and the package tests, each `xcodebuild` piped through `scripts/filter-xcode-log.sh`.
The iOS scope block is self-tested by `scripts/check-ios-scope.sh` with fixtures, which also
checks that every `BUILD_FILES` entry of `scripts/build-kmp-framework.sh` matches `IOS_PATHS`.
`shared-uitest/` is not in `IOS_PATHS` today (S1 adds it). The gate's iOS duration on this
machine was not measured for this plan.

**F9. Protected paths (verified with `scripts/check-protected-paths.sh --files`; the new paths
as reported by the S1a spike).** Protected:
`docs/epics/ios-ui-tests.md` (`/docs/epics/`), `iosApp/TrailMetrics.xcodeproj/**` (project and
every shared scheme, a new one included), `.github/workflows/ci.yml`, `scripts/pre-push-check.sh`,
`scripts/classify-changes.sh`, `scripts/check-ios-scope.sh`, `scripts/check-ios-scope-fixtures/**`,
`scripts/build-kmp-framework.sh`, `settings.gradle.kts`, every `build.gradle.kts` (the new
`shared-uitest/build.gradle.kts` included), `iosApp/Packages/*/Package.swift`,
`docs/architecture/**`, `iosApp/.swiftlint.yml`, `.claude/skills/tm-pr-workflow/SKILL.md` (and the
rest of `.claude/` except the four reference skills). Not protected: `shared-uitest/src/**`,
`iosApp/TrailMetrics/*.swift` and new files under it, `iosApp/TrailMetricsUITests/**`, the
package Views, `README.md`, `shared/README.md`, `.claude/skills/tm-kmp-shared/SKILL.md`,
`.claude/skills/tm-testing/SKILL.md`, `.claude/skills/tm-ios/SKILL.md`, `BOARD.md`.

**F10. Board ordering (verified).** The record had `After: agentic-dev-loop`, and
`agentic-dev-loop` (Order 40) is still on the board, while its Done when item (1) needs this
work. Read literally the two waited for each other. Q8 (resolved in #138).

The findings F11 to F22 come from the S1a spike, 2026-10-13, Xcode 27.0, Apple M4; they were
reported by the spike run and not re-run by this PR. All spike builds used CI's flags
`ARCHS=arm64 EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO` (F20) and printed `xcodebuild` output
through `scripts/filter-xcode-log.sh`.

**F11. A test-only module builds a variant of the framework (S1a spike).** A new KMP module
`shared-uitest` (targets `iosArm64` and `iosSimulatorArm64`, SKIE, `api(project(":shared"))`,
one DEBUG-only static framework with `baseName = "TrailMetricsShared"` that exports `:shared`,
`:domain`, `:data` and `:core`) builds with
`./gradlew :shared-uitest:assembleTrailMetricsSharedDebugXCFramework`. The nine seam files of
PR #141 (branch `feature/ios-ui-tests-seam`) compiled in it unchanged, and its 14 tests
(`UiTestEntryTest` 4, `UiTestFakesTest` 10) pass in about 4 s with
`./gradlew :shared-uitest:iosSimulatorArm64Test`. The gate's `allTests` picks the module up on
its own. `shared/build.gradle.kts` and the root `build.gradle.kts` did not change.

**F12. Swift API of the variant (S1a spike).** Compared as sets of normalised declaration lines
(SKIE's per-build counters normalised): the `.swiftinterface` (simulator and device) and the
`.apinotes` of the variant contain everything the production framework has plus only the
`UiTest*` declarations; the `KoinHelper`, `KoinInitIosKt` and `ActivityHistoryRepository`
blocks are byte-identical. One difference in the Objective-C header: two Kotlin methods named
`cancel` (Ktor `ByteReadChannel`/`ByteWriteChannel` with a `Throwable`, and coroutines `Job`
with a `CancellationException`) get their Swift labels swapped (`cancel(cause:)` and
`cancel(cause_:)` change places). No Swift code in the app or the packages calls either. So an
identical production API is **not** guaranteed by construction. **Not verified:** whether
another `export(...)` order avoids the swap.

**F13. Swift-visible seam (S1a spike).** `UiTestScenario` (enum, 5 cases), `UiTestControls`
(four `Int` counters, `releaseHeldCalls()`) and `doInitKoinIosForUiTest(scenario:)` with its
file class `UiTestEntryKt`. The fakes, the fixtures, the Koin module and `UiTestHeldCall` are
not visible.

**F14. Build times and sizes (S1a spike, local).** Production framework cold 13.1 s, warm
1.7 s. Variant cold right after the production build 8.0 s (it does not rebuild `domain`,
`data`, `core` or `shared`; it compiles itself and links twice), warm 1.5 s. Sizes:
production 144 MB, variant 145 MB (simulator binary +212 KB).

**F15. Linking without a `Package.swift` change, and the stale-variant bug (S1a spike).** The
variant copied over the existing path `shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework`
is picked up by `xcodebuild` (the app compiles unchanged against it); copying the production
framework back is picked up too (checked with `strings` counts in derived data: 2 hits, then 0).
`SharedKit/Package.swift` does not change. **Problem:** the scheme pre-action printed "KMP
shared framework is up to date" while the variant was in place, because
`scripts/build-kmp-framework.sh` hashes only the Kotlin sources and build files, not which
framework is in place. A normal build could silently link a variant left behind. D1 fixes this
in S1.

**F16. Swift side under a compile condition (S1a spike).** A custom compile condition
`UITEST_SEAM` around a call of `doInitKoinIosForUiTest(scenario:)` in `TrailMetricsApp.swift`:
against the production framework with the condition off, the app builds; with the condition
on, it fails ("cannot find 'UiTestScenario'", "cannot find 'doInitKoinIosForUiTest'");
against the variant with the condition on, it builds. A throwaway UI test launched the app
with the scenario `FailedDelete`, opened History and found the seeded "Running" row (10.7 s);
the same test against the normal scheme failed with "Seeded activity not shown" (negative
control). The seam's NSLog line was not seen in `simctl log show`; not investigated.

**F17. Setting the condition: a build configuration, named `Debug-UITest` (S1a spike).** Both
ways work. (1) A command-line override of `SWIFT_ACTIVE_COMPILATION_CONDITIONS` reaches the app
and every Swift package and keeps `DEBUG`, but it writes into the same `Debug-iphonesimulator`
products as normal builds and changes every package's flags. (2) A third build configuration
(`project.pbxproj` +152 lines: a copy of Debug in all four configuration lists, the project
level adds `UITEST_SEAM`) plus a new shared scheme `TrailMetricsUITests.xcscheme` with Test and
Launch on it: `xcodebuild -list` shows it, the normal scheme's build is unchanged, the UI-test
scheme builds and runs `LaunchUITests` (passed). The configuration is the one to use.
Surprise: a configuration named `UITest` makes Xcode build the SwiftPM packages as Release
(`-O`, whole-module, no `DEBUG`); named `Debug-UITest` they build as Debug. The packages do not
see `UITEST_SEAM`; only the app does, and only the app needs it.

**F18. What the pre-action sees (S1a spike).** `CONFIGURATION=Debug` and
`SCHEME_NAME=TrailMetrics` for the normal scheme; `CONFIGURATION=Debug-UITest` and
`SCHEME_NAME=TrailMetricsUITests` for the UI-test scheme, for both build and test.
`CONFIGURATION` is the more robust signal (it survives an explicit `-configuration`). The gate
and CI call the script outside Xcode and need an explicit argument such as `--variant uitest`.

**F19. No seam in normal builds (S1a spike).** `strings` counts for `doInitKoinIosForUiTest` /
`UiTestScenario`: Debug-UITest framework 8 / 129, Debug-UITest app dylib 2 / 10; Debug
framework, Debug dylib and Debug app 0 / 0; Release app binary 0 / 0 (`KoinHelper` 2 as the
positive control).

**F20. `xcodebuild build` needs CI's architecture flags (S1a spike).** Without
`ARCHS=arm64 EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO` an `xcodebuild build` on clean derived
data fails (28 errors in Tracking: the XCFramework has no x86_64 slice), also without any change
from this epic. CI and the gate pass those flags. No document in the repo gives a complete
`xcodebuild build` command (board record `xcodebuild-build-needs-arm64-flags-undocumented`).

**F21. detekt does not lint KMP sources (S1a spike; to be verified in the board task).**
`./gradlew detekt` is NO-SOURCE for `shared` and `domain` today (and for `shared-uitest` in the
spike), so the gate's detekt does not lint KMP sources. True before this epic (board record
`detekt-skips-kmp-source-sets`).

**F22. Not verified by the S1a spike:** CI's Xcode 26.6; a real device build; build and test
times on CI; the Xcode IDE (only `xcodebuild` was used); whether another `export` order avoids
the `cancel` label swap (F12).

## Decisions (proposed; the human approves or changes them)

**D1 (replaced 2026-10-13). Fake seam: a test-only variant of the shared framework, entered
through a launch argument under `#if UITEST_SEAM`.** Replaces the old D1, which compiled the
fakes into the production XCFramework and guarded the Swift call site with `#if DEBUG`.
- **Kotlin.** A new KMP module `shared-uitest` (package `dev.roozbahani.trailmetrics.uitest`)
  holds the seam and its tests (`src/iosMain`, `src/iosTest`). It has the targets `iosArm64`
  and `iosSimulatorArm64`, applies SKIE, depends on `api(project(":shared"))` and defines one
  DEBUG-only static framework with `baseName = "TrailMetricsShared"` that exports `:shared`,
  `:domain`, `:data` and `:core` (F11). It is the same Swift module as production with the same
  API plus the seam. `shared` itself is unchanged: production code never depends on
  `shared-uitest`.
- **Seam API.** `doInitKoinIosForUiTest(scenario)` calls `initKoin()` and then
  `loadKoinModules(uiTestOverrideModule)`, never `initKoin { modules(...) }`, whose modules the
  production modules would replace (F2, verified in S0). The override module binds in-memory
  Kotlin fakes for `LocationRepository`, `TrackingServiceLauncher` (no-op),
  `DirectionsRepository`, `ActivityHistoryRepository` (a `MutableStateFlow`, so History updates
  live) and `UserProfileRepository`, scripted by an enum `UiTestScenario`. No database, HTTP
  client, `CLLocationManager` or user defaults is touched (Koin singles are lazy and nothing
  resolves the replaced ones; **verified** for an overridden single and the Room database, S0
  spike; S1's tests keep proving it for the real seam). Swift sees exactly three declarations:
  `doInitKoinIosForUiTest(scenario:)`, `UiTestScenario` and the controls class (F13). No
  `suspend` function and no `Flow` is exposed to Swift; everything else is `internal`.
- Scripting per scenario lives in the enum: start location, a fixed closed route around it
  (directions ignore the waypoints), location updates that walk that route to its end, a saved
  profile (so Start Tracking never opens the sheet), seeded history, and which calls are held
  (`CompletableDeferred` gates) or fail. No delays and no real clock: a held call waits until
  the test releases it.
- **Build script.** `scripts/build-kmp-framework.sh` builds either the production framework or
  the variant and copies the variant over the existing debug path
  `shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework` (F15), so
  `SharedKit/Package.swift` does not change. The variant is chosen by `CONFIGURATION ==
  Debug-UITest` inside Xcode (pre-action and the `--build-phase` safety net alike, F18), and by
  `--variant uitest` from the gate and CI. The stamp records the variant together with the
  input hash, so switching between the two always rebuilds and copies; that fixes the
  stale-variant bug of F15. The input hash also covers `shared-uitest/src` and
  `shared-uitest/build.gradle.kts`. After building the variant the script checks that the
  variant's normalised Objective-C header and Swift interface equal production's plus `UiTest*`
  declarations only, and fails otherwise. That check must deal with F12: S1 first tries another
  `export(...)` order; if the `cancel` label swap stays, the check normalises exactly that swap
  and nothing else, and the PR says which case applies.
- **Swift.** The test launches the app with `-uiTestScenario <name>`. `TrailMetricsApp.init()`
  reads it inside `#if UITEST_SEAM` and calls `doInitKoinIosForUiTest(scenario:)` instead of
  `doInitKoinIos()`; the probe overlay and every file under `iosApp/TrailMetrics/UITestSupport/`
  are under the same condition. `UITEST_SEAM` is set only in the project-level `Debug-UITest`
  build configuration (D2). This replaces the `#if DEBUG` guard of the old D1. A build with the
  condition against the production framework fails to compile (F16), so the condition and the
  variant cannot drift apart silently.
- **Probe.** In UI-test mode only, the app shows a small overlay (top centre, clear of the
  existing corner buttons) with a text element `uitest.probe` (for example
  `directions=1 directionsDone=1 saves=1 deletes=1`), a button `uitest.probe.refresh` that
  re-reads the counters, and a button `uitest.probe.release` that completes every held call.
  "One directions request" and "one deletion" are counters (UI evidence cannot tell one call
  from two identical ones); "one History entry" is checked both by the History row count and by
  the save counter.
- **Normal builds.** Debug and Release builds of the app and the production framework contain
  no seam code, Kotlin or Swift (F19: `strings` counts 0 / 0). S2 and S3 show the counts again
  for the real seam.
- Cost: one new Gradle module (the nine files of #141 plus the build file), one more mode in
  the framework script with its API check, one build configuration and one scheme in the
  project (D2), and one Swift file plus the call site in the app target. CI builds the variant
  once more (D3).

Options compared:
- **(b) a separate UI-test host app target with its own entry point.** Stronger Swift-side
  separation than (a), but a second app target in the protected `project.pbxproj` and a second
  app build in CI, and on its own it does not keep the Kotlin fakes out of the production
  framework. The third build configuration of this D1 takes the useful part of (b) (a separate
  compile condition) without a second target.
- **(c) Swift fakes passed into Kotlin** (`doInitKoinIos(overrides:)` taking Swift objects,
  reusing the `TestSupport` patterns). Needs live `Flow`s that Swift cannot emit (F3), boxed
  `Result` values, SKIE `__` names and linking test code from a Sources target, which
  `TestSupport` forbids. Rejected.
- **(d) environment variable instead of a launch argument.** Equivalent; the argument is
  easier to see in a failing test's log. Either is fine.
- **The fakes in the production XCFramework, entered through `#if DEBUG`** (the old D1, PR
  #141). Rejected by the human on 2026-10-13 (Q1): test code would ship in every build of the
  framework, Release included.
- **A Gradle property on one module** that adds the seam sources to `shared`'s own framework.
  Rejected: less explicit; "no seam in production" would hold only by the property's default,
  and the production module's build file would carry test wiring.
- **A command-line override of `SWIFT_ACTIVE_COMPILATION_CONDITIONS`** instead of a build
  configuration (F17, way 1). Rejected: it shares the `Debug-iphonesimulator` products with
  normal builds and changes every package's flags.

**D2 (replaced 2026-10-13). Build configuration `Debug-UITest` and a dedicated scheme
`TrailMetricsUITests`.** The UI-test target itself already exists (#140, the old D2: agent-edited
`project.pbxproj`, synchronized group `TrailMetricsUITests/`, `LaunchUITests`). S2 adds:
- A project build configuration `Debug-UITest`, a copy of Debug in all configuration lists,
  with `UITEST_SEAM` added to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` at the project level. The
  name must contain `Debug`: named `UITest`, Xcode builds the SwiftPM packages as Release (F17).
- A shared scheme `TrailMetricsUITests` with the same Build pre-action as `TrailMetrics`, and
  its Test and Launch actions on `Debug-UITest`. The UI testables and the build-for-testing
  `TrailMetricsUITests` entry move from the `TrailMetrics` scheme to the new one, so the
  normal scheme and CI's "Build iOS app" command stay as they are.
- The PR is protected: Ali reviews and merges it. If `xcodebuild -list` or the build rejects
  the hand edit within the retry budget, the agent stops, and Ali creates the configuration and
  the scheme in Xcode and pushes them to the S2 branch; the agent continues from there (as the
  old D2 provided for the target).

**D3 (updated 2026-10-13). CI: two additions to the existing iOS job, no new required check
(Q4).**
- `:shared-uitest:iosSimulatorArm64Test` joins the Gradle "Run iOS simulator tests" step.
- After "Run iOS package tests", a last step "Run iOS UI tests"
  (`if: steps.changes.outputs.decision != 'light'`): `scripts/build-kmp-framework.sh --variant
  uitest`, then `xcodebuild test -project TrailMetrics.xcodeproj -scheme TrailMetricsUITests
  -destination "platform=iOS Simulator,id=$SIM_ID" -resultBundlePath <dir> -skipMacroValidation
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO`, on the same
  simulator as the package tests. It runs last because it leaves the variant at the debug path.
  Then "Upload UI test results" with `actions/upload-artifact@v7`,
  `if: failure() && steps.<ui>.outcome == 'failure'`, `continue-on-error: true`. On `light` all
  are skipped like every other heavy step. The CI secrets config holds only the placeholder, so
  the result bundle carries no real key; a local result bundle is never uploaded.
- Time (reasoned, **not measured** on CI; S4 measures it): variant build +1 to 2 min, UI-test
  app build for a concrete simulator 1.3 to 3 min (it does not reuse the generic build's
  products), simulator already booted by the package tests, 15 to 40 s per scenario: about
  **+4 to 8 min** instead of the +3 to 6 min estimated before, so a full iOS job of about 20 to
  24 min against the timeout of 40. Locally the variant builds in 1.5 to 8 s (F14) and five
  scenarios take about 1.5 to 2.5 min (S0). A job above 30 min is a stop-and-report for the
  human, not a reason to drop tests.
- S4 also fixes the stale comment above "Room schema export freshness" (board record
  `drift-ci-schema-freshness-comment-converter`), because it touches `ci.yml`.
- The PR touches `.github/workflows/`: the machine token cannot push it, so the agent writes the
  branch and the PR body to `~/agent-workspace/pr-body-<branch-slug>.md` and Ali pushes and merges.

**D4 (updated 2026-10-13). Local gate smoke: one scenario, only for an iOS UI or ViewModel diff
(Q6).** The smoke is the failed-delete scenario (S3): no map gesture, no held call, the
shortest path through launch, seam, History and Details. A new regex in the gate's iOS scope
block, in the style of `IOS_PATHS`:
`IOS_UI_PATHS='^(iosApp/TrailMetrics/|iosApp/TrailMetricsUITests/|iosApp/Packages/[^/]+/Sources/|shared/src/(commonMain|iosMain)/|shared-uitest/)'`
(markdown excluded as today) sets `TOUCHES_IOS_UI`; the step runs only when the iOS steps run
and `TOUCHES_IOS_UI` is true, last in the iOS part (after "iOS package tests"): `scripts/build-kmp-framework.sh
--variant uitest`, then `xcodebuild test -scheme TrailMetricsUITests
-only-testing:TrailMetricsUITests/<SmokeClass>/<smokeTest>` with CI's architecture flags and the
output through `scripts/filter-xcode-log.sh` (the local secrets config holds a real Maps key).
Cost (S1a spike, local, reported): 36 to 47 s for the UI-test build and run (warm / fresh
derived data), plus about 6 s on the next normal build, which switches the variant back. Needs
`scripts/pre-push-check.sh`, `scripts/check-ios-scope.sh` and new fixtures: all protected, so
Ali merges; the agent can push it (no workflow file).

**D5. Determinism rules for every UI test.**
- One `XCUIApplication().launch()` per test with its scenario argument; the in-memory fakes
  start empty on every launch, so no test depends on another or on simulator state.
- Wait on identifiers or texts with `waitForExistence(timeout:)` (10 s); for an absence, first
  wait for a positive signal (a probe counter or a screen change), then assert the element does
  not exist. No `sleep`, no `Thread.sleep`, no fixed delays in tests or fakes.
- UI-test mode turns off UIKit animations (`UIView.setAnimationsEnabled(false)`).
- Held calls are released only by `uitest.probe.release`; nothing depends on timing between
  two taps except the double tap itself, which is the behavior under test.
- `continueAfterFailure = false`; SwiftLint `--strict` applies to test code (no force unwraps).
- Each scenario PR checks once, in the working tree, that its test fails when the ViewModel
  guard is removed (as `tm-testing` asks for the Compose double-tap tests), and says in the PR
  if it does not (see S6, Generate twice).

**D6. Flake policy (fits `tm-agent-loop` sections 6 and 8).** A red UI test on CI is red: the
agent does not re-run, does not merge, reports the run URL, the failing test and the result
bundle artifact, and the human decides about a re-run. No `-retry-tests-on-failure`, no
`XCTSkip`, no `continue-on-error` on the test step, no removal from the required iOS check
(Q5). A UI test that failed once without a related change gets a BOARD.md record with the
result bundle's failure screenshot and log, so flakes are fixed at the cause (a missing wait
or a timing-dependent fake), not retried away.

**D7. Identifiers only where text cannot find the element** (the `tm-testing` rule for test
tags). Needed: `route.generateButton` (its label changes to a spinner), `route.resetButton`
(image-only top-bar Reset), `route.map` (the long-press target), `history.activityRow`,
`details.deleteButton` (image-only trash). Not needed: "Start Tracking", "Start", "Finish",
"Delete", "OK", the "Error" alert title. These are product-code changes in `Route` and
`History`; `Tracking` needs none. `route.resetButton` stays although the button already
exposes `arrow.clockwise` (F6): the symbol name is incidental and may change with the design.

## The five scenarios

| Scenario | Fake script (`UiTestScenario`) | Steps | Assertion | Identifiers | Risk / fallback |
|---|---|---|---|---|---|
| Failed delete shows "Error" (smoke) | one seeded activity; delete fails | History tab, tap row, tap trash, tap "Delete" | alert "Error" with the general message exists; after "OK" the Details screen is still shown; probe `deletes=0` | `history.activityRow`, `details.deleteButton` | low: the seeded row is shown through the variant (F16) |
| Delete confirmation twice | one seeded activity; deletes held | row, trash, "Delete" (held), trash, "Delete" again, release | probe `deletes=1`; History shows no row ("No Activities yet") | same | low. A literal double tap on the alert's button cannot work (the alert closes on the first tap), so "twice" means a second confirmation while the first delete is in flight, as Android's `DetailsScreenTest` does |
| Generate twice | start location; 3 long-presses; directions held | long-press map 3x, double-tap Generate, release | wait for "Start Tracking"; probe `directions=1` | `route.map`, `route.generateButton` | low for the map: the long press is verified (S0). The View disables Generate while loading, so the test may pass even without `RouteViewModel`'s guard; then it proves the user-visible outcome, and the guard stays proven by the unit test. The PR states which |
| Generate then Reset | as above, directions held | long-press 3x, tap Generate, tap top-bar Reset, release | probe `directionsDone=1`, then "Start Tracking" does not exist and Generate is disabled (no waypoints) | `route.map`, `route.generateButton`, `route.resetButton` | low: the map long press is verified (S0) |
| Finish twice | route = small closed loop (at most 10 points); location updates walk it to the end; profile saved; saves held | long-press 3x, Generate, "Start Tracking", "Start", wait for "Finish", double-tap "Finish", release, History tab | probe `saves=1`; exactly one `history.activityRow` | the Route ones, `history.activityRow` | highest: `isRouteCompleted` with location updates delivered at once (**not verified**; the walk and the loop size are tuned in S7). Snapshot of a key-less map is a blank image, which is fine |

What XCUITest cannot see: the polyline and markers inside `GMSMapView` (not accessibility
elements we rely on), so "no route afterwards" is proven by the panel that exists only while a
route exists, not by the drawing. The map long press needs no fallback: S0 showed it works
(F6), so Q3 is not needed. The two delete scenarios do not depend on the map.

## Subtasks

Every `xcodebuild` command of a subtask passes CI's `ARCHS=arm64 EXCLUDED_ARCHS=x86_64
ONLY_ACTIVE_ARCH=NO` (F20) and prints through `scripts/filter-xcode-log.sh`.

```yaml
- id: S0
  title: Spike (local only, no PR) - XCUITest feasibility and timings
  branch: chore/ios-ui-tests-spike (local, deleted afterwards, never pushed)
  skills: [tm-ios, tm-testing]
  depends_on: []
  allowed_paths: []   # S0 is a local spike in a throwaway worktree; nothing is committed.
  protected: n/a (no PR)
  acceptance:
    - >-
      A report (comment on this plan's PR or a message to the human) answering, with the
      commands used: (1) does an XCUITest long-press on the GMSMapView add a waypoint, with
      the CI placeholder key and with no key (Generate becomes enabled after 3); (2) does the
      app launch without a blocking alert under the placeholder key; (3) does a later Koin
      module override an earlier binding in Koin 4.2.2; (4) local times for a concrete
      simulator build-for-testing, one launch and one scenario; (5) the simulator runtimes on
      the CI macOS image (from a CI log or `xcrun simctl list runtimes` in a run the human
      triggers), because the app needs iOS 26.5. (5) can be answered first from the public
      list of installed simulator runtimes of the `macos-latest` runner image; run a CI step
      only if that list is unclear.
    - >-
      If (1) or (5) fails, the agent stops; the human decides Q3 and the plan is changed.
  tier2: none (no change reaches main)
  outcome:   # S0 spike, 2026-10-13, Xcode 27.0
    - >-
      Done; acceptance met. (1) works with the CI placeholder key (F6); with no key the app
      crashes before the map exists (Risks, Maps key). (2) launches with no alert and no crash
      under the placeholder key. (3) verified (F2). (4) below. (5) verified (F7).
    - >-
      The worktree had to be given a placeholder configuration by Ali, because the agent may
      not create or name that file, and under Xcode 27 the app does not build without it.
    - >-
      Local timings (Apple M4, Xcode 27.0, GoogleMaps from the local package cache, XCFramework
      already built), each measured twice: cold build-for-testing 13.5 to 17.7 s, warm 2.1 to
      2.6 s; launch until the first Route element 4.2 to 5.0 s; one scenario (launch, 3 long
      presses, one assertion) 10.5 to 11.8 s; a whole `xcodebuild test` of 4 to 5 tests about
      80 s including an incremental build.
    - >-
      The UI-test target and LaunchUITests of the old S2 landed in #140. The old S1 (seam inside
      shared, PR #141) was closed unmerged on 2026-10-13 (Q1); its code is reused by the new S1.
    - >-
      The S1a spike (2026-10-13, local, no PR) tested the test-only variant: F11 to F22.

- id: S1
  title: Add the test-only framework variant (ADR amendment, shared-uitest module, build script)
  branch: feature/ios-ui-tests-variant
  skills: [tm-kmp-shared, tm-testing, tm-pr-workflow]
  depends_on: [S0]
  protected: yes (settings.gradle.kts, shared-uitest/build.gradle.kts, scripts, docs/architecture) - agent pushes, Ali merges
  allowed_paths:
    - settings.gradle.kts
    - shared-uitest/**
    - scripts/build-kmp-framework.sh
    - scripts/pre-push-check.sh
    - scripts/check-ios-scope.sh
    - scripts/check-ios-scope-fixtures/**
    - docs/architecture/ADR-002-shared-umbrella-module.md
    - docs/architecture/OVERVIEW.md
    - .claude/skills/tm-kmp-shared/SKILL.md
    - .claude/skills/tm-testing/SKILL.md
    - shared/README.md
    - README.md
  commits:   # in this order, one PR (Q11)
    - >-
      docs: amend ADR-002 (the rule that only shared applies SKIE and defines binaries.framework)
      with the wording of Q10, OVERVIEW.md (module table, build section), tm-kmp-shared (the
      'only module allowed to export' line), shared/README.md, README.md
    - >-
      the module shared-uitest with the seam and its tests (the nine files of #141, taken from
      the branch feature/ios-ui-tests-seam, package dev.roozbahani.trailmetrics.uitest)
    - >-
      scripts/build-kmp-framework.sh variant support (D1), its input hash covering
      shared-uitest/src and its build file, the API check; scripts/pre-push-check.sh and
      scripts/check-ios-scope.sh (IOS_PATHS, BUILD_FILES) with their fixtures; tm-testing
  acceptance:
    - >-
      ADR-002 and tm-kmp-shared say that shared stays the only module that exports production
      API to iOS and that shared-uitest builds only a test-only variant of the same framework,
      linked by UI-test builds alone (Q10).
    - >-
      doInitKoinIosForUiTest(scenario) starts Koin with the production modules plus the
      override module; UiTestScenario has the five scenarios of the table; a controls object
      exposes the counters and releaseHeldCalls().
    - >-
      kotlin.test cases in shared-uitest's iosTest (run by `./gradlew
      :shared-uitest:iosSimulatorArm64Test`, also by `allTests` in the gate) show per scenario
      that KoinHelper returns the fakes, that saves and deletes update observeActivities, that
      a held call completes only after release, that a failing delete throws, that no
      TrailMetricsDatabase and no real IosLocationRepositoryImpl is created, and stopKoin after
      each test; a test fails if the fakes are passed through `initKoin { }` instead (F2).
    - >-
      Swift-visible surface, named so `tm-pr-review` item 6 can judge it: exactly the
      top-level function doInitKoinIosForUiTest(scenario), the enum UiTestScenario and a
      controls class with plain non-suspend members (Int counters, releaseHeldCalls()). No
      `suspend` function and no `Flow` is exposed to Swift, so nothing can throw into Swift
      and no `@Throws` is needed (`tm-kmp-shared`, "`@Throws` policy"); the fakes' own
      `@Throws` suspend members implement the existing interfaces unchanged.
    - >-
      The production framework's header and Swift interface are unchanged by this PR (normalised
      diff against main's build, command and output in the PR); doInitKoinIos and initKoin are
      unchanged.
    - >-
      `scripts/build-kmp-framework.sh` picks the variant by CONFIGURATION == Debug-UITest or
      --variant uitest; the stamp records the variant; the stale-variant problem of F15 is gone:
      a normal run right after a variant run rebuilds and copies (real output in the PR).
    - >-
      The API check passes for the variant and fails on a planted extra declaration (checked
      once in the working tree); the PR says whether another export order removed the cancel
      label swap (F12) or the check normalises exactly that swap.
    - >-
      The root build.gradle.kts and shared/build.gradle.kts need no change. If one does, the
      agent stops and reports (the S1a spike needed none).
    - >-
      `scripts/classify-changes.sh` classifies a shared-uitest/** change as full (checked, with
      output; the script itself is not changed); `scripts/check-ios-scope.sh --self-test` has a
      fixture for a shared-uitest/ file and passes.
    - >-
      shared-uitest has no Kover floor: it has no Android or JVM target, so Kover measures
      nothing in it, and its build file does not read config/kover-floors.properties (as
      `shared`).
  tier2: none - no user-visible change; nothing calls the seam yet

- id: S2
  title: Add the Debug-UITest configuration and the TrailMetricsUITests scheme
  branch: chore/ios-ui-tests-config-scheme
  skills: [tm-ios, tm-testing]
  depends_on: [S1]
  protected: yes (xcodeproj) - agent pushes, Ali merges
  allowed_paths:
    - iosApp/TrailMetrics.xcodeproj/project.pbxproj
    - iosApp/TrailMetrics.xcodeproj/xcshareddata/xcschemes/TrailMetrics.xcscheme
    - iosApp/TrailMetrics.xcodeproj/xcshareddata/xcschemes/TrailMetricsUITests.xcscheme
    - iosApp/TrailMetricsUITests/LaunchUITests.swift
    - .claude/skills/tm-ios/SKILL.md
  acceptance:
    - >-
      `xcodebuild -list -project iosApp/TrailMetrics.xcodeproj` shows the configuration
      Debug-UITest and both schemes.
    - >-
      The normal scheme's generic `xcodebuild build -scheme TrailMetrics` and the package tests
      pass unchanged; the TrailMetrics scheme no longer lists the UI testables.
    - >-
      `xcodebuild test -scheme TrailMetricsUITests -destination 'platform=iOS Simulator,id=<sim>'`
      builds the variant through the pre-action and runs LaunchUITests; the PR quotes the test
      count and duration.
    - >-
      Under Debug-UITest the Swift packages build as Debug (the PR says how it was checked, for
      example `-Onone` and DEBUG in the package compile lines of the build log).
    - >-
      The `strings` counts of F19 for Debug, Release and Debug-UITest are in the PR, with the
      commands.
    - >-
      LaunchUITests' comment about the Maps key is corrected: with an empty key the app crashes
      on the Route tab (board record maps-empty-api-key-crashes-route-tab).
    - >-
      tm-ios describes the configuration, the scheme and which framework each one links.
  tier2: none - project configuration and scheme only

- id: S3
  title: Wire the seam into the app under UITEST_SEAM, add the probe and the failed-delete scenario
  branch: feature/ios-ui-tests-failed-delete
  skills: [tm-ios, tm-testing]
  depends_on: [S1, S2]
  protected: no
  allowed_paths:
    - iosApp/TrailMetrics/TrailMetricsApp.swift
    - iosApp/TrailMetrics/UITestSupport/**
    - iosApp/TrailMetricsUITests/Support/**
    - iosApp/TrailMetricsUITests/DetailsFailedDeleteUITests.swift
    - iosApp/Packages/History/Sources/History/HistoryView.swift
    - iosApp/Packages/History/Sources/History/DetailsView.swift
    - .claude/skills/tm-testing/SKILL.md
    - .claude/skills/tm-ios/SKILL.md
  acceptance:
    - >-
      Without the launch argument the app starts exactly as before (doInitKoinIos path); the
      call site, the probe and every file under UITestSupport are inside `#if UITEST_SEAM`.
    - >-
      `strings` counts for doInitKoinIosForUiTest and UiTestScenario are 0 in the Debug and the
      Release app and framework builds and above 0 in Debug-UITest (commands and output in the
      PR).
    - >-
      The probe overlay shows only in UI-test mode; identifiers history.activityRow and
      details.deleteButton exist; nothing else in the Views changes.
    - >-
      The app is built with the placeholder Maps key (the CI step that writes the placeholder
      configuration, or the local one); with an empty key the app crashes (Risks, Maps key).
    - >-
      The failed-delete test passes locally 3 runs out of 3 through the TrailMetricsUITests
      scheme; with the delete fake set to succeed it fails (checked once in the working tree).
    - >-
      tm-testing gets an "XCUITest" section (variant, seam, probe, D5 rules); tm-ios's
      composition-root lines mention the UITEST_SEAM-only UI-test entry.
  tier2: DetailsFailedDeleteUITests (XCUITest) covers the "Error" alert of a failed delete

- id: S4
  title: Run the variant tests and the UI tests in CI's iOS job and upload the result bundle on failure
  branch: chore/ios-ui-tests-ci
  skills: [tm-pr-workflow]
  depends_on: [S1, S2]
  protected: yes (.github/workflows) - agent writes branch and PR body file, Ali pushes and merges
  allowed_paths:
    - .github/workflows/ci.yml
  acceptance:
    - >-
      The Gradle iOS simulator test step also runs `:shared-uitest:iosSimulatorArm64Test`.
    - >-
      The last step "Run iOS UI tests" runs `scripts/build-kmp-framework.sh --variant uitest`
      and then `xcodebuild test -scheme TrailMetricsUITests` on the same concrete simulator as
      the package tests, with CI's architecture flags; it is skipped on `light` and has no
      continue-on-error; the upload step runs only when it failed.
    - >-
      The PR's CI run shows the steps green and their durations; the PR states the full iOS job
      time against the 40-minute timeout (above 30 min: stop and report).
    - >-
      The CI step that writes the placeholder configuration runs before "Run iOS UI tests"
      (it already does in the current job order; S4 keeps it that way).
    - >-
      The comment above "Room schema export freshness" speaks of entity changes only (board
      record drift-ci-schema-freshness-comment-converter; the record is removed by a later PR
      that may edit BOARD.md, since S4 cannot push and its allowed_paths have no BOARD.md).
    - >-
      CI's existing list of script self-test steps also runs
      `scripts/check-variant-api.sh --self-test` (the gate already runs it; a workflow change,
      so S4 adds it).
  tier2: none - CI only

- id: S5
  title: Add the delete-confirmed-twice scenario
  branch: feature/ios-ui-tests-delete-twice
  skills: [tm-ios, tm-testing]
  depends_on: [S3]
  protected: no
  allowed_paths:
    - iosApp/TrailMetricsUITests/DetailsDeleteTwiceUITests.swift
  acceptance:
    - >-
      Passes 3 of 3 locally; fails with DetailsViewModel's isDeleteStarted guard removed
      (checked once in the working tree, the failure message quoted in the PR).
  tier2: DetailsDeleteTwiceUITests covers one deletion for two confirmations

- id: S6
  title: Add the Generate-twice and Generate-then-Reset scenarios
  branch: feature/ios-ui-tests-route
  skills: [tm-ios, tm-testing]
  depends_on: [S3]
  protected: no
  allowed_paths:
    - iosApp/TrailMetricsUITests/Route/**
    - iosApp/Packages/Route/Sources/Route/RouteView.swift
  acceptance:
    - >-
      route.map, route.generateButton, route.resetButton identifiers exist; nothing else in
      RouteView changes.
    - >-
      Every map long press lasts at least 1 s (`press(forDuration:)`), inside the map area
      (F6).
    - >-
      Both tests pass 3 of 3 locally. Generate then Reset fails with RouteViewModel's
      stale-result guard removed. For Generate twice the PR says whether removing the
      generationTask guard makes the test fail or whether the View's disabled state already
      prevents the second request.
  tier2: RouteGenerateTwiceUITests, RouteGenerateThenResetUITests

- id: S7
  title: Add the Finish-twice scenario and remove the BOARD.md record
  branch: feature/ios-ui-tests-finish-twice
  skills: [tm-ios, tm-testing, tm-pr-workflow]
  depends_on: [S4, S5, S6]
  protected: no
  allowed_paths:
    - iosApp/TrailMetricsUITests/Tracking/**
    - shared-uitest/src/**
    - BOARD.md
  acceptance:
    - >-
      Passes 3 of 3 locally and in the PR's CI run; fails with TrackingViewModel's
      isSessionSaved guard removed.
    - >-
      Every map long press lasts at least 1 s, inside the map area (F6).
    - >-
      Any change to the scenario's route or walk stays in shared-uitest with its test.
    - >-
      The last commit removes the record test-ios-ui-double-tap-and-stale-results
      (chore(board)) and its slug from the agentic-dev-loop record's Refs; `rg` finds the slug
      nowhere outside docs/epics/ (historical plans stay as written); check-board passes.
    - >-
      The same commit narrows the agentic-dev-loop record's Done when item (1): the iOS
      UI-test target, seam and CI suite are done; the iOS local-gate smoke stays listed
      unless S8 is already merged.
  tier2: TrackingFinishTwiceUITests covers one History entry for two Finish taps

- id: S8
  title: Run the smoke UI test in the local gate for iOS UI and ViewModel diffs
  branch: chore/ios-ui-tests-gate-smoke
  skills: [tm-pr-workflow]
  depends_on: [S1, S3]
  protected: yes (scripts, .claude) - agent pushes, Ali merges
  allowed_paths:
    - scripts/pre-push-check.sh
    - scripts/check-ios-scope.sh
    - scripts/check-ios-scope-fixtures/**
    - .claude/skills/tm-pr-workflow/SKILL.md
  acceptance:
    - >-
      IOS_UI_PATHS includes shared-uitest/; `scripts/check-ios-scope.sh --self-test` has
      fixtures for a package Sources file (smoke runs), an app-target file (runs), a
      shared-uitest/ file (runs), a Tests/ file only (does not run), a domain-only file (does
      not run), markdown only (does not run).
    - >-
      The smoke step runs last in the iOS part, builds the variant with `--variant uitest` and
      runs one test through the TrailMetricsUITests scheme and filter-xcode-log.sh.
    - >-
      A gate run on a branch touching HistoryView.swift runs the smoke step and reports its
      time; a docs-only branch does not.
    - >-
      tm-pr-workflow Tier 1 describes the step.
  tier2: none - gate only
```

| Id | Title | depends_on | Protected | Pushes / merges |
|---|---|---|---|---|
| S0 | Spike: feasibility and timings | - | n/a (no PR) | nobody (local) |
| S1 | Test-only framework variant: ADR amendment, `shared-uitest`, build script | S0 | yes | agent / Ali |
| S2 | `Debug-UITest` configuration + `TrailMetricsUITests` scheme | S1 | yes | agent / Ali |
| S3 | App wiring under `UITEST_SEAM`, probe, failed delete (smoke) | S1, S2 | no | agent / agent or Ali |
| S4 | CI steps (variant tests, UI tests) | S1, S2 | yes (workflow) | Ali / Ali |
| S5 | Delete twice | S3 | no | agent / agent or Ali |
| S6 | Generate twice, Generate then Reset | S3 | no | agent / agent or Ali |
| S7 | Finish twice, board record removed | S4, S5, S6 | no | agent / agent or Ali |
| S8 | Local gate smoke | S1, S3 | yes | agent / Ali |

Why this differs from the suggested shape (seam, identifiers, target, CI, scenarios, gate): the
identifiers are not a subtask of their own. An identifier with no test is unverified dead
weight, and spread over S3 and S6 each lands with the test that uses it, in disjoint files.
The seam is no longer a small unprotected Kotlin package: keeping it out of the production
framework (Q1) needs an architecture exception, a new module and build-script support, which
belong together in one protected PR (S1, Q11), because none of the three is useful or testable
without the other two. The configuration and scheme (S2) are a separate protected project diff,
small enough for Ali to review on its own, and they need S1's variant to build. S0 came first
because three of five scenarios depend on one unverified gesture; the S1a spike checked the
variant mechanism before this plan was rewritten around it.

## Waves

- Wave 0: S0 (local, done) and the S1a spike (local, done).
- Wave 1: S1 (alone: it changes the build script, the gate script and the module set that every
  later subtask builds on).
- Wave 2: S2 (alone: it needs S1's variant to build the UI-test scheme).
- Wave 3: S3 || S4. Disjoint: app target, `UITests/Support/**`, one test file, the History Views
  and two reference skills vs `.github/workflows/ci.yml`.
- Wave 4: S5 || S6 || S8. Disjoint: one Details test file vs `UITests/Route/**` and
  `RouteView.swift` vs `scripts/pre-push-check.sh`, `scripts/check-ios-scope.sh`, its fixtures
  and `tm-pr-workflow`. S5 and S6 both run the iOS gate steps; default cap of two concurrent
  subtasks (`epic-orchestration`), so S8 waits if the machine is busy.
- Wave 5: S7.

Hotspots: `scripts/build-kmp-framework.sh` only in S1. `iosApp/TrailMetrics.xcodeproj/**`
(project and both schemes) only in S2. `iosApp/TrailMetrics/**` and
`iosApp/TrailMetricsUITests/Support/**` only in S3 (later scenarios read them, never edit them;
a missing helper goes into the scenario's own file). `shared-uitest/src/**` in S1 and S7,
different waves. `scripts/pre-push-check.sh`, `scripts/check-ios-scope.sh` and its fixtures in
S1 and S8, different waves. `tm-ios` in S2 and S3, `tm-testing` in S1 and S3, different waves.

## Risks and what could go wrong

- **API drift between production and variant** (F12): the variant's Objective-C header swaps
  the Swift labels of two `cancel` methods. No Swift code uses them today, but an identical API
  is not guaranteed by construction. Mitigation: the API check in the framework script (D1),
  which normalises exactly that swap if another `export` order does not remove it; any other
  difference fails the build.
- **Stale variant at the debug path** (F15): the current script would link a leftover variant
  silently. S1 records the variant in the stamp; its acceptance shows the switch back with real
  output. The UI-test step runs last in CI and in the gate for the same reason.
- **Configuration naming** (F17): a configuration whose name lacks `Debug` builds the SwiftPM
  packages as Release. S2 keeps `Debug-UITest` and checks the package flags.
- **Architecture flags** (F20): `xcodebuild` without `ARCHS=arm64 EXCLUDED_ARCHS=x86_64
  ONLY_ACTIVE_ARCH=NO` fails on clean derived data. Every command of this epic passes them;
  the documentation gap is board record `xcodebuild-build-needs-arm64-flags-undocumented`.
- **Xcode IDE and Xcode 26.6 not verified** (F22): the S1a spike used only `xcodebuild` under
  Xcode 27.0. S2's and S4's CI runs are the first checks under 26.6; opening the project in the
  IDE with the new configuration and scheme is checked by Ali when reviewing S2. The first CI run
  (PR #148) showed that Xcode 26.6 writes Swift module-qualified extension names with `.`
  (`extension TrailMetricsShared.UiTestScenario`) and Xcode 27 with `::`; the variant API check
  now accepts both.
- **Map long-press not reachable** (F6): closed, S0 showed the long press works (S0 spike,
  2026-10-13, Xcode 27.0).
- **Maps key at launch:** **verified** (S0 spike, 2026-10-13, Xcode 27.0): the CI placeholder
  key launches the app with no alert and no crash, and the long press works. An EMPTY key
  crashes the app at launch of the Route tab (`GMSMapView.init` raises in `GMSServices
  checkServicePreconditions`; the app skips `configure` but `RouteMapView` still creates the
  map; board record `maps-empty-api-key-crashes-route-tab`). So the step that writes the
  placeholder configuration is a hard prerequisite of the UI-test step, in CI and in any local
  worktree. Locally the real key loads map tiles during UI tests (network use, no assertion
  depends on it).
- **Missing base configuration file:** under Xcode 27 a missing base configuration file is a
  build error, not a warning (S0 spike, 2026-10-13, Xcode 27.0). CI is not affected: it writes
  the file first.
- **CI time:** +4 to 8 min estimated (D3), not measured on CI; measured in S4. If the full job
  nears 30 min, stop and report (Q4 alternative: a separate job).
- **Flakes:** XCUITest on a shared CI simulator; the package suite already had a timing flake
  (`RouteViewModelPendingEventsTests ... isDeliveredOnceToNextStreamOnly`). D5 and D6 apply;
  the risk remains and the policy is to report, not retry.
- **Finish-twice determinism:** location updates arrive at once; SwiftUI may coalesce
  `currentPath` changes so route progress jumps; S7 tunes the loop length to the progress
  search window (10) and checks 3 of 3.
- **Kotlin test support in the production framework** (F4): pre-existing and separate from
  this epic. The UI-test seam no longer reaches normal Debug or Release builds (F19), but
  `SwiftTestSupport.kt` still does (board records `swift-test-support-ships-in-production-framework`
  and `release-build-links-debug-xcframework`).
- **detekt does not lint KMP sources** (F21): neither `shared-uitest` nor the existing KMP
  modules are linted by the gate's detekt today; board record `detekt-skips-kmp-source-sets`.
- **Probe overlay hides a control:** placed top centre; S3 checks no existing test target
  element is covered on the smallest simulator in use.
- **Koin override behavior:** verified in S0 (F2); S1's tests keep it proven for the real seam.

## Questions for the human and the human's answers

1. **Seam (D1).** Kotlin fakes in `shared/src/iosMain/.../uitest/` shipped in the XCFramework
   like `SwiftTestSupport`, entered only through a `#if DEBUG` launch argument?
   Recommendation (#138): yes. Other choice: a separate UI-test host target or configuration,
   about +1.5 min CI and a larger protected project diff, and still the same Kotlin binary.
   **Answer (2026-10-13, replaces the earlier "Yes"):** No. The UI-test fakes must not be part
   of the production XCFramework; a separate test-only XCFramework variant is built instead
   (D1). The earlier answer was withdrawn after the human saw the trade-off in PR #141, which
   was closed unmerged.
2. **Project file (D2).** The agent hand-edits `project.pbxproj` and the scheme; you review and
   merge. Recommendation: yes, with you creating the target in Xcode only if the edit fails.
   Other choice: you create the empty target first (a few minutes of your time, one more
   hand-off).
   **Answer:** Yes. The agent edits `project.pbxproj` and the scheme; Ali creates the empty
   target in Xcode only if the edit fails within the retry budget. (Applies the same way to the
   configuration and the new scheme of S2.)
3. **Only if S0 shows the map long-press fails:** add a UI-test-only way to add waypoints in
   `RouteView` (product code, DEBUG only), or keep Generate twice, Generate then Reset and
   Finish twice on unit tests plus a human check. Recommendation: the DEBUG-only seam; the
   other choice leaves three of five scenarios unproven by UI tests.
   **Answer:** Not needed unless S0 shows the map long-press fails. If it does, the agent
   stops and reports; Ali decides then (recommendation of the plan stays: a DEBUG-only seam).
   **Outcome:** not needed: S0 showed the long press works (F6; S0 spike, 2026-10-13,
   Xcode 27.0).
4. **CI placement (D3).** A step in the existing iOS job (no new required check, no
   branch-protection change). Recommendation: yes. Other choice: a separate job, which needs a
   new required status check in branch protection (your setting) and a second simulator boot.
   **Answer:** Yes. A step in the existing iOS job; no new required check.
5. **Flake policy (D6).** No automatic retries. Recommendation: yes. Other choice:
   `-retry-tests-on-failure -test-iterations 2` would hide real races in exactly the behavior
   these tests exist to catch.
   **Answer:** Yes. No automatic test retries.
6. **Gate trigger (D4).** Smoke only for `IOS_UI_PATHS`. Recommendation: yes. Other choice:
   whenever the iOS steps run (simpler, about 45 s more on every domain or data change, D4).
   **Answer:** Yes. The smoke test runs in the local gate only for `IOS_UI_PATHS`.
7. **No integration branch.** Recommendation: a chain of PRs on `main`; every step is green and
   invisible to users. Other choice: `feature/epic/ios-ui-tests` with a ruleset and a final epic
   merge by you.
   **Answer:** Yes. A chain of PRs on `main`, no integration branch.
8. **Board order (F10).** The record waits for `agentic-dev-loop`, whose item (1) waits for this
   work. Recommendation: you drop the record's `After` line when you approve this plan (a
   subtask may not do it: `tm-pr-workflow` Board rules 5 and 6 keep parallel subtasks and
   PRs that do not resolve a record off it); S7 removes the record and narrows
   `agentic-dev-loop` item (1) to what remains (S8 never edits `BOARD.md`). Other choice: leave the `After`
   and treat this plan's approval as the exception, which leaves the board saying something
   the work does not follow.
   **Answer:** Ali drops the record's `After: agentic-dev-loop` line; done in the PR that
   records these answers. S7 still removes the record and narrows `agentic-dev-loop` item (1).
9. **Release builds.** `SharedKit/Package.swift` links the DEBUG XCFramework for every build
   configuration (F4), so a Release app already contains Kotlin debug code
   (`SwiftTestSupport.kt`). Since the rewrite of D1 the UI-test fakes are not in it: they are
   built only into the test-only variant, and a Release app binary has 0 seam strings (F19).
   **Answer:** not fixed in this epic. A separate BOARD.md record,
   `release-build-links-debug-xcframework`, covers a Release XCFramework before any
   distribution build.
10. **ADR-002 exception (new, 2026-10-13).** Amend ADR-002 and the module-boundary rule of
    `tm-kmp-shared` so that one test-only module may build a variant of the framework?
    Proposed wording for the amendment (S1 makes it): "`shared` stays the only module that
    exports production API to iOS; `shared-uitest` builds only a test-only variant of the same
    framework, linked by UI-test builds alone."
    **Answer (2026-10-13):** Yes.
11. **PR grouping (new, 2026-10-13).** Recommendation: the ADR amendment, the new module and
    the variant support in the build script are ONE PR (S1); the Xcode configuration and scheme
    are one PR (S2); the CI step is a workflow PR (S4); the local-gate smoke is S8.
    **Answer (2026-10-13):** Yes.

## Done (record test-ios-ui-double-tap-and-stale-results)

Checked against its Done when: "a UI-test target exists in the shared scheme" (#140, and the
dedicated shared scheme `TrailMetricsUITests` of S2) "with a launch-time fake seam" (S1, S3:
the test-only variant and the `UITEST_SEAM` call site), "and XCUITest scenarios cover" Finish
twice (S7), Generate then Reset (S6), Generate twice (S6), delete confirmation twice (S5),
failed delete (S3). This plan also requires them to run in CI (S4), because a test that nothing
runs proves nothing; S7 depends on S4 for that reason. S8 is `agentic-dev-loop` item (1)'s
local-gate part, not part of this record.

## Epic-level Tier 2

- All five scenarios green in CI's iOS job on `main` after S7, on the CI simulator, through
  the `TrailMetricsUITests` scheme against the test-only variant.
- The normal app is unaffected: the `strings` counts of S2 and S3 show no seam code in Debug
  and Release builds (F19 shape), and CI's "Build iOS app" step is unchanged.
- Nothing needs a human on a device for these five behaviors. What stays manual is unchanged
  and outside this plan: the map's drawn route and markers, real GPS, permission dialogs, the
  Live Activity and notifications (`agentic-dev-loop` item (6)), checked before releases.
- No final smoke check: no user-visible behavior changes.
