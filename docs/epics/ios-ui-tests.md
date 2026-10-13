# Epic: iOS UI tests (XCUITest) for double taps, stale results and the delete error

- **Slug:** ios-ui-tests
- **Status:** approved by the human with the answers below when this plan is merged
- **Source:** BOARD.md record `test-ios-ui-double-tap-and-stale-results` (Order 100), and item (1)
  of the `agentic-dev-loop` record's Done when (the iOS half of "a deterministic test seam and
  UI-test targets ... a fast smoke subset in the local gate ... the full UI suite in CI").
- **Integration branch:** none (recommended, Q7). A chain of PRs against `main`, each leaving
  `main` green and the app unchanged for users: every subtask adds test infrastructure or a
  test, never half a feature.
- **Goal:** `xcodebuild test -scheme TrailMetrics` runs an XCUITest target against the real app,
  launched with deterministic fakes for location, directions, user profile, history storage and
  the tracking launcher, and five scenarios prove what today only ViewModel unit tests prove:
  Finish tapped twice saves one History entry; Generate then Reset leaves no route; Generate
  tapped twice sends one directions request; the delete confirmation given twice deletes once;
  a failed delete shows the "Error" alert. CI's iOS job runs the suite; the local gate runs one
  smoke scenario when the diff touches iOS UI or ViewModel code.
- **Out of scope:** Android (done: the Compose UI tests of `feature-history`, `feature-route`,
  `feature-tracking`); any user-visible behavior change; the map's drawn content (polylines,
  markers); real GPS, permission dialogs, the Live Activity, notifications (they stay on the
  `agentic-dev-loop` manual device list); new third-party dependencies; Release-build tooling for
  the shared XCFramework.
- **Approved by:** Ali Roozbahani, by merging the PR that contains this text (2026-10-13)

Evidence is from the files on `main` at `42dc442` and from read-only commands run on
2026-10-12 (Xcode 27.0, Swift 6.4, one local simulator runtime: iOS 26.5). Every claim below is
marked **verified** (read in a file or seen in a command's output) or **not verified** (a
belief that a subtask must check). Nothing was built or run for this plan.

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
4.2.2 (`koinBom`). Whether Koin 4 allows a later module to override a definition by default
is **not verified** in this repo; S1's test proves it or S1 uses an explicit module list.

**F3. Existing Swift fakes do not fit the app (verified).** `TestSupport`
(`FakeLocationRepository`, `FakeActivityHistoryRepository`, `FakeUserProfileRepository`) and
`Route/Tests/.../FakeDirectionsRepository` are written for unit tests: `observeActivities()`
emits a fixed list and does not reflect saves or deletes (a History screen would never show a
new entry), Swift cannot emit into a Kotlin `Flow`, and `TestSupport/Package.swift` says the
product is linked only from `.testTarget`s, never from a Sources target. Their scripting ideas
(hold a call until released, count calls, fail on demand) carry over.

**F4. Kotlin test support already ships in the XCFramework (verified).**
`shared/src/iosMain/.../testsupport/SwiftTestSupport.kt` is "TEST SUPPORT ONLY" and is compiled
into the framework because a second Kotlin framework cannot share its types.
`SharedKit/Package.swift` points at the **debug** XCFramework for every build configuration,
so today no Kotlin code can be kept out of a Release app build (verified for the package path;
whether anyone builds Release is not known).

**F5. Xcode project (verified).** `xcodebuild -list`: targets `TrailMetrics` and
`TrackingWidgetExtension`; configurations Debug and Release; schemes include the shared
`TrailMetrics`. `project.pbxproj` has `objectVersion = 77` and uses
`PBXFileSystemSynchronizedRootGroup`s for `TrailMetrics/` and `TrackingWidget/`: a new file in
those folders joins its target without a project-file edit, and a new target needs one new
synchronized group plus the target, its build configurations, a target dependency and a
product reference. The project-level deployment target is iOS 26.5. The shared scheme has a
Build pre-action (`scripts/build-kmp-framework.sh`), one BuildActionEntry (the app) and a
`TestAction` with no Testables (`shouldAutocreateTestPlan = "YES"`). Debug defines `DEBUG`
in `SWIFT_ACTIVE_COMPILATION_CONDITIONS`.

**F6. What XCUITest can reach in the Views (verified from the source; reachability at runtime
not verified).**
- Route: Generate is a `Button` whose label switches between the text "Generate Route" and a
  `ProgressView` while loading, and it is `.disabled(!canGenerateRoute)`
  (`canGenerateRoute` needs a start point, at least 3 waypoints and not loading). The top-bar
  Reset and the profile button are image-only. The `StartTrackingPanel` (text buttons "Reset"
  and "Start Tracking") is shown only while a generated route and a start point exist.
- Waypoints are added only by a **long press on the `GMSMapView`**
  (`RouteMapView.Coordinator.mapView(_:didLongPressAt:)`). Every Route and Tracking scenario
  therefore needs XCUITest to long-press the map and the Maps SDK to report it. **Not
  verified**, and the biggest risk of the plan (S0).
- Tracking: "Start", "Finish" are text-labelled. Finish appears only after
  `isRouteCompleted` (tracking state, last location within 25 m of the last planned point,
  progress index near the end). Finish writes a snapshot request that `TrackingMapView`
  answers, then calls `onFinishClicked(snapshotFilePath:onSaved:)`; `onSaved` dismisses.
- History rows are `Button`s in a `LazyVStack` (no identifier). Details' Back and Delete
  (trash) are image-only buttons; the confirmation is an `.alert("Delete this activity?")`
  with a "Delete" button; the failure is an `.alert("Error")` with the message
  `HistoryErrorMessage.general` and an "OK" button.
- Map content inside `GMSMapView` is not asserted by any scenario.

**F7. CI iOS job (verified, `.github/workflows/ci.yml` and `gh run view`).** Steps after
"Classify changes", all skipped on `decision == 'light'`: "Select Xcode", "Install SwiftLint",
"Run SwiftLint", JDK, Gradle, "Build KMP
Shared Framework", "Run iOS simulator tests" (Gradle), "Generate" the secrets config with a CI
placeholder key, "Build iOS app" (`xcodebuild build`, `generic/platform=iOS Simulator`),
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
The iOS scope block is self-tested by `scripts/check-ios-scope.sh` with fixtures. The gate's
iOS duration on this machine was not measured for this plan.

**F9. Protected paths (verified with `scripts/check-protected-paths.sh --files`).** Protected:
`docs/epics/ios-ui-tests.md` (`/docs/epics/`), `iosApp/TrailMetrics.xcodeproj/**` (project and
scheme), `.github/workflows/ci.yml`, `scripts/pre-push-check.sh`, `scripts/classify-changes.sh`,
`scripts/check-ios-scope.sh`, `scripts/check-ios-scope-fixtures/**`, `iosApp/.swiftlint.yml`,
`shared/build.gradle.kts`, `.claude/skills/tm-pr-workflow/SKILL.md` (and the rest of `.claude/`
except the four reference skills). Not protected: `iosApp/TrailMetrics/*.swift` and new files
under it, a new `iosApp/TrailMetricsUITests/`, the package Views, new Kotlin files under
`shared/src/iosMain/` and `shared/src/iosTest/`, `.claude/skills/tm-testing/SKILL.md`,
`.claude/skills/tm-ios/SKILL.md`, `BOARD.md`.

**F10. Board ordering (verified).** The record has `After: agentic-dev-loop`, and
`agentic-dev-loop` (Order 40) is still on the board, while its Done when item (1) needs this
work. Read literally the two wait for each other. Q8.

## Decisions (proposed; the human approves or changes them)

**D1. Fake seam: a launch argument read by the composition root picks a Kotlin override
module (option a).**
- The test launches the app with `-uiTestScenario <name>`. `TrailMetricsApp.init()` reads it
  inside `#if DEBUG` and calls a new Kotlin entry `doInitKoinIosForUiTest(scenario)` instead
  of `doInitKoinIos()`; without the argument, or in a Release build, the code path is the one
  that exists today.
- `doInitKoinIosForUiTest` (new, `shared/src/iosMain/.../uitest/`) starts Koin with the
  production modules plus one override module that binds in-memory Kotlin fakes for
  `LocationRepository`, `TrackingServiceLauncher` (no-op), `DirectionsRepository`,
  `ActivityHistoryRepository` (a `MutableStateFlow`, so History updates live) and
  `UserProfileRepository`, scripted by an enum `UiTestScenario`. No database, HTTP client,
  `CLLocationManager` or user defaults is touched (Koin singles are lazy and nothing resolves
  the replaced ones; **not verified**, S1 checks the database part).
- Scripting per scenario lives in the enum: start location, a fixed closed route around it
  (directions ignore the waypoints), location updates that walk that route to its end, a saved
  profile (so Start Tracking never opens the sheet), seeded history, and which calls are held
  (`CompletableDeferred` gates) or fail. No delays and no real clock: a held call waits until
  the test releases it.
- The test reads results through a **probe**: in UI-test mode only, the app shows a small
  overlay (top centre, clear of the existing corner buttons) with a text element
  `uitest.probe` (for example `directions=1 directionsDone=1 saves=1 deletes=1`), a button
  `uitest.probe.refresh` that re-reads the counters, and a button `uitest.probe.release` that
  completes every held call. "One directions request" and "one deletion" are counters (UI
  evidence cannot tell one call from two identical ones); "one History entry" is checked both
  by the History row count and by the save counter.
- Release builds: the Swift call site and the overlay are inside `#if DEBUG`, so a Release app
  cannot enter UI-test mode. The Kotlin fakes are compiled into the XCFramework like
  `SwiftTestSupport.kt` (F4); keeping them out would need Release XCFramework tooling that does
  not exist. Check (S3 acceptance): a Release build's app binary does not contain the string
  `-uiTestScenario`.
- Cost: one Kotlin package (about 5 small fakes, one enum, one entry function, one controls
  object) with its `iosTest`, one Swift file in the app target, no project-file change for
  the seam itself.

Options compared:
- **(b) a separate UI-test host app target or a third build configuration** with its own entry
  point. Stronger Swift-side separation, but a larger protected `project.pbxproj` diff, a second
  app build in CI (about +1.5 min, F7) and the same Kotlin situation (F4). Rejected unless the
  human wants it (Q1).
- **(c) Swift fakes passed into Kotlin** (`doInitKoinIos(overrides:)` taking Swift objects,
  reusing the `TestSupport` patterns). Needs live `Flow`s that Swift cannot emit (F3), boxed
  `Result` values, SKIE `__` names and linking test code from a Sources target, which
  `TestSupport` forbids. Rejected.
- **(d) environment variable instead of a launch argument.** Equivalent to (a); the argument is
  easier to see in a failing test's log. Either is fine.

**D2. Test target: `TrailMetricsUITests`, agent-edited project file (Q2).** A
`com.apple.product-type.bundle.ui-testing` target with `TEST_TARGET_NAME = TrailMetrics`, a
synchronized root group `TrailMetricsUITests/` (so later test files need no project edit), a
dependency on the app target, and a Testables entry plus a build-for-testing-only
BuildActionEntry in the shared `TrailMetrics` scheme. A build-for-testing-only entry is not
part of `xcodebuild build`, so the existing generic build and the package tests stay as they
are (**not verified**; S2 acceptance). The PR is protected: Ali reviews and merges it in any
case. If `xcodebuild -list` or the build rejects the hand edit within the retry budget, the
agent stops, and Ali creates the empty target in Xcode (File > New > Target > UI Testing
Bundle, add it to the shared scheme's Test action) and pushes it to the S2 branch; the agent
continues from there.

**D3. CI: one more step in the existing iOS job, no new required check (Q4).** After "Run iOS
package tests", a step "Run iOS UI tests" (`if: steps.changes.outputs.decision != 'light'`):
same simulator selection as the package tests, `xcodebuild test -project
TrailMetrics.xcodeproj -scheme TrailMetrics -destination "platform=iOS Simulator,id=$SIM_ID"
-only-testing:TrailMetricsUITests -resultBundlePath <dir> -skipMacroValidation
CODE_SIGNING_ALLOWED=NO`. Then "Upload UI test results" with `actions/upload-artifact@v7`,
`if: failure() && steps.<ui>.outcome == 'failure'`, `continue-on-error: true`. On `light` both
are skipped like every other heavy step. The CI secrets config holds only the placeholder, so
the result bundle carries no real key; a local result bundle is never uploaded.
Time (**not verified**, S0 measures locally, S4 on CI): one app build for a concrete simulator
(1 to 3 min, it does not reuse the generic build's products), simulator already booted by the
package tests, about 5 to 10 s per app launch and 15 to 40 s per scenario: **+3 to 6 min**,
so a full iOS job of about 15 to 22 min against the timeout of 40. A job above 30 min is a
stop-and-report for the human, not a reason to drop tests.
The PR touches `.github/workflows/`: the machine token cannot push it, so the agent writes the
branch and the PR body to `~/agent-workspace/pr-body-<branch-slug>.md` and Ali pushes and merges.

**D4. Local gate smoke: one scenario, only for an iOS UI or ViewModel diff (Q6).** The smoke
is the failed-delete scenario (S3): no map gesture, no held call, the shortest path through
launch, seam, History and Details. A new regex in the gate's iOS scope block, in the style of
`IOS_PATHS`: `IOS_UI_PATHS='^(iosApp/TrailMetrics/|iosApp/TrailMetricsUITests/|iosApp/Packages/[^/]+/Sources/|shared/src/(commonMain|iosMain)/)'`
(markdown excluded as today) sets `TOUCHES_IOS_UI`; the step runs only when the iOS steps run
and `TOUCHES_IOS_UI` is true, after "iOS package tests", with
`-only-testing:TrailMetricsUITests/<SmokeClass>/<smokeTest>` and the output through
`scripts/filter-xcode-log.sh` (the local secrets config holds a real Maps key). Cost (**not
verified**): one concrete-simulator app build plus one launch, estimated 1.5 to 3 min on top of
today's iOS steps. Needs `scripts/pre-push-check.sh`, `scripts/check-ios-scope.sh` and new
fixtures: all protected, so Ali merges; the agent can push it (no workflow file).

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
`History`; `Tracking` needs none.

## The five scenarios

| Scenario | Fake script (`UiTestScenario`) | Steps | Assertion | Identifiers | Risk / fallback |
|---|---|---|---|---|---|
| Failed delete shows "Error" (smoke) | one seeded activity; delete fails | History tab, tap row, tap trash, tap "Delete" | alert "Error" with the general message exists; after "OK" the Details screen is still shown; probe `deletes=0` | `history.activityRow`, `details.deleteButton` | low |
| Delete confirmation twice | one seeded activity; deletes held | row, trash, "Delete" (held), trash, "Delete" again, release | probe `deletes=1`; History shows no row ("No Activities yet") | same | low. A literal double tap on the alert's button cannot work (the alert closes on the first tap), so "twice" means a second confirmation while the first delete is in flight, as Android's `DetailsScreenTest` does |
| Generate twice | start location; 3 long-presses; directions held | long-press map 3x, double-tap Generate, release | wait for "Start Tracking"; probe `directions=1` | `route.map`, `route.generateButton` | map long-press (S0). The View disables Generate while loading, so the test may pass even without `RouteViewModel`'s guard; then it proves the user-visible outcome, and the guard stays proven by the unit test. The PR states which |
| Generate then Reset | as above, directions held | long-press 3x, tap Generate, tap top-bar Reset, release | probe `directionsDone=1`, then "Start Tracking" does not exist and Generate is disabled (no waypoints) | `route.map`, `route.generateButton`, `route.resetButton` | map long-press (S0) |
| Finish twice | route = small closed loop (at most 10 points); location updates walk it to the end; profile saved; saves held | long-press 3x, Generate, "Start Tracking", "Start", wait for "Finish", double-tap "Finish", release, History tab | probe `saves=1`; exactly one `history.activityRow` | the Route ones, `history.activityRow` | highest: map long-press (S0) and `isRouteCompleted` with location updates delivered at once (**not verified**; the walk and the loop size are tuned in S7). Snapshot of a key-less map is a blank image, which is fine |

What XCUITest cannot see: the polyline and markers inside `GMSMapView` (not accessibility
elements we rely on), so "no route afterwards" is proven by the panel that exists only while a
route exists, not by the drawing. **Fallback if S0 shows the map long-press does not work:**
the three Route/Tracking scenarios cannot reach Generate without a product seam; the options
are a UI-test-only way to add waypoints (a `RouteView` change, Q3) or keeping those three on
their unit tests plus a human check under reason 2 of `tm-pr-workflow` Tier 2. The two delete
scenarios do not depend on the map.

## Subtasks

```yaml
- id: S0
  title: Spike (local only, no PR) - XCUITest feasibility and timings
  branch: chore/ios-ui-tests-spike (local, deleted afterwards, never pushed)
  skills: [tm-ios, tm-testing]
  depends_on: []
  allowed_paths: []   # S0 is a local spike in a throwaway worktree; nothing is committed.
  acceptance:
    - A report (comment on this plan's PR or a message to the human) answering, with the
      commands used: (1) does an XCUITest long-press on the GMSMapView add a waypoint, with
      the CI placeholder key and with no key (Generate becomes enabled after 3); (2) does the
      app launch without a blocking alert under the placeholder key; (3) does a later Koin
      module override an earlier binding in Koin 4.2.2; (4) local times for a concrete
      simulator build-for-testing, one launch and one scenario; (5) the simulator runtimes on
      the CI macOS image (from a CI log or `xcrun simctl list runtimes` in a run the human
      triggers), because the app needs iOS 26.5. (5) can be answered first from the public
      list of installed simulator runtimes of the `macos-latest` runner image; run a CI step
      only if that list is unclear.
    - If (1) or (5) fails, the agent stops; the human decides Q3 and the plan is changed.
  tier2: none (no change reaches main)

- id: S1
  title: Add the UI-test fake seam in shared (Kotlin) with its tests
  branch: feature/ios-ui-tests-seam
  skills: [tm-kmp-shared, tm-testing]
  depends_on: [S0]
  allowed_paths:
    - shared/src/iosMain/kotlin/dev/roozbahani/trailmetrics/shared/uitest/**
    - shared/src/iosTest/kotlin/dev/roozbahani/trailmetrics/shared/uitest/**
  acceptance:
    - doInitKoinIosForUiTest(scenario) starts Koin with the production modules plus the
      override module; UiTestScenario has the five scenarios of the table; a controls object
      exposes the counters and releaseHeldCalls().
    - kotlin.test cases in iosTest (run by `./gradlew :shared:iosSimulatorArm64Test`, also in
      the gate and CI) show per scenario that KoinHelper returns the fakes, that saves and
      deletes update observeActivities, that a held call completes only after release, that a
      failing delete throws, that no TrailMetricsDatabase instance is created, and stopKoin
      after each test.
    - In UI-test mode the real `IosLocationRepositoryImpl` and `TrailMetricsDatabase` are
      never created (a test proves it).
    - doInitKoinIos and initKoin are unchanged (git diff shows no change outside allowed_paths).
    - Swift-visible surface, named in the task so `tm-pr-review` item 6 can judge it: the
      top-level function doInitKoinIosForUiTest(scenario), the enum UiTestScenario and a
      controls class with plain non-suspend members (Int counters, releaseHeldCalls()). No
      `suspend` function and no `Flow` is exposed to Swift, so nothing can throw into Swift
      and no `@Throws` is needed (`tm-kmp-shared`, "`@Throws` policy"); the fakes' own
      `@Throws` suspend members implement the existing interfaces unchanged.
  tier2: none - no user-visible change; nothing calls the seam yet

- id: S2
  title: Add the TrailMetricsUITests target to the project and the shared scheme
  branch: chore/ios-ui-tests-target
  skills: [tm-ios, tm-testing]
  depends_on: [S0]
  allowed_paths:
    - iosApp/TrailMetrics.xcodeproj/project.pbxproj
    - iosApp/TrailMetrics.xcodeproj/xcshareddata/xcschemes/TrailMetrics.xcscheme
    - iosApp/TrailMetricsUITests/LaunchUITests.swift
    - .claude/skills/tm-pr-workflow/SKILL.md
    - .claude/skills/epic-orchestration/SKILL.md
  acceptance:
    - `xcodebuild -list -project iosApp/TrailMetrics.xcodeproj` lists TrailMetricsUITests.
    - The gate's generic `xcodebuild build -scheme TrailMetrics` and the package tests pass
      unchanged.
    - `xcodebuild test -scheme TrailMetrics -destination 'platform=iOS Simulator,id=<sim>'
      -only-testing:TrailMetricsUITests` runs LaunchUITests (launch, the Route and History tab
      buttons exist) and passes; the PR quotes the test count and duration.
    - The lines in tm-pr-workflow (Tier 2, reasons 1 and 2) and the epic-orchestration worked
      example that say iOS has no UI-test target are updated to what is now true, and no
      longer name the record test-ios-ui-double-tap-and-stale-results (so S7 can remove it
      without touching protected skills).
  tier2: none - test target only
  protected: yes (xcodeproj, .claude) - agent pushes, Ali merges

- id: S3
  title: Wire the seam into the app, add the probe and the failed-delete scenario
  branch: feature/ios-ui-tests-failed-delete
  skills: [tm-ios, tm-testing]
  depends_on: [S1, S2]
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
    - Without the launch argument the app starts exactly as before (doInitKoinIos path);
      the UI-test code is inside `#if DEBUG`; a Release simulator build's app binary does
      not contain the string `-uiTestScenario` (command and output in the PR).
    - The probe overlay shows only in UI-test mode; identifiers history.activityRow and
      details.deleteButton exist; nothing else in the Views changes.
    - The failed-delete test passes locally 3 runs out of 3; with the delete fake set to
      succeed it fails (checked once in the working tree).
    - tm-testing gets an "XCUITest" section (seam, probe, D5 rules); tm-ios's composition-root
      lines mention the DEBUG-only UI-test entry.
  tier2: DetailsFailedDeleteUITests (XCUITest) covers the "Error" alert of a failed delete

- id: S4
  title: Run the UI tests in CI's iOS job and upload the result bundle on failure
  branch: chore/ios-ui-tests-ci
  skills: [tm-pr-workflow]
  depends_on: [S2]
  allowed_paths:
    - .github/workflows/ci.yml
  acceptance:
    - The new step runs `-only-testing:TrailMetricsUITests` on the same concrete simulator as
      the package tests, is skipped on `light`, has no continue-on-error; the upload step runs
      only when it failed.
    - The PR's CI run shows the step green and its duration; the PR states the full iOS job
      time against the 40-minute timeout.
  tier2: none - CI only
  protected: yes (.github/workflows) - agent writes branch and PR body file, Ali pushes and merges

- id: S5
  title: Add the delete-confirmed-twice scenario
  branch: feature/ios-ui-tests-delete-twice
  skills: [tm-ios, tm-testing]
  depends_on: [S3]
  allowed_paths:
    - iosApp/TrailMetricsUITests/DetailsDeleteTwiceUITests.swift
  acceptance:
    - Passes 3 of 3 locally; fails with DetailsViewModel's isDeleteStarted guard removed
      (checked once in the working tree, the failure message quoted in the PR).
  tier2: DetailsDeleteTwiceUITests covers one deletion for two confirmations

- id: S6
  title: Add the Generate-twice and Generate-then-Reset scenarios
  branch: feature/ios-ui-tests-route
  skills: [tm-ios, tm-testing]
  depends_on: [S3]
  allowed_paths:
    - iosApp/TrailMetricsUITests/Route/**
    - iosApp/Packages/Route/Sources/Route/RouteView.swift
  acceptance:
    - route.map, route.generateButton, route.resetButton identifiers exist; nothing else in
      RouteView changes.
    - Both tests pass 3 of 3 locally. Generate then Reset fails with RouteViewModel's
      stale-result guard removed. For Generate twice the PR says whether removing the
      generationTask guard makes the test fail or whether the View's disabled state already
      prevents the second request.
  tier2: RouteGenerateTwiceUITests, RouteGenerateThenResetUITests

- id: S7
  title: Add the Finish-twice scenario and remove the BOARD.md record
  branch: feature/ios-ui-tests-finish-twice
  skills: [tm-ios, tm-testing, tm-pr-workflow]
  depends_on: [S4, S5, S6]
  allowed_paths:
    - iosApp/TrailMetricsUITests/Tracking/**
    - shared/src/iosMain/kotlin/dev/roozbahani/trailmetrics/shared/uitest/**
    - shared/src/iosTest/kotlin/dev/roozbahani/trailmetrics/shared/uitest/**
    - BOARD.md
  acceptance:
    - Passes 3 of 3 locally and in the PR's CI run; fails with TrackingViewModel's
      isSessionSaved guard removed.
    - Any change to the scenario's route or walk stays in the uitest package with its test.
    - The last commit removes the record test-ios-ui-double-tap-and-stale-results
      (chore(board)) and its slug from the agentic-dev-loop record's Refs; `rg` finds the slug
      nowhere outside docs/epics/ (historical plans stay as written); check-board passes.
    - The same commit narrows the agentic-dev-loop record's Done when item (1): the iOS
      UI-test target, seam and CI suite are done; the iOS local-gate smoke stays listed
      unless S8 is already merged.
  tier2: TrackingFinishTwiceUITests covers one History entry for two Finish taps

- id: S8
  title: Run the smoke UI test in the local gate for iOS UI and ViewModel diffs
  branch: chore/ios-ui-tests-gate-smoke
  skills: [tm-pr-workflow]
  depends_on: [S3]
  allowed_paths:
    - scripts/pre-push-check.sh
    - scripts/check-ios-scope.sh
    - scripts/check-ios-scope-fixtures/**
    - .claude/skills/tm-pr-workflow/SKILL.md
  acceptance:
    - `scripts/check-ios-scope.sh --self-test` has fixtures for a package Sources file (smoke
      runs), an app-target file (runs), a Tests/ file only (does not run), a domain-only file
      (does not run), markdown only (does not run).
    - A gate run on a branch touching HistoryView.swift runs the smoke step through
      filter-xcode-log.sh and reports its time; a docs-only branch does not.
    - tm-pr-workflow Tier 1 describes the step.
  tier2: none - gate only
  protected: yes (scripts, .claude) - agent pushes, Ali merges
```

| Id | Title | depends_on | Protected | Pushes / merges |
|---|---|---|---|---|
| S0 | Spike: feasibility and timings | - | n/a (no PR) | nobody (local) |
| S1 | Kotlin seam + tests | S0 | no | agent / agent if `tm-agent-loop` section 8 holds, else Ali |
| S2 | UI-test target + scheme | S0 | yes | agent / Ali |
| S3 | App wiring, probe, failed delete (smoke) | S1, S2 | no | agent / agent or Ali |
| S4 | CI step | S2 | yes (workflow) | Ali / Ali |
| S5 | Delete twice | S3 | no | agent / agent or Ali |
| S6 | Generate twice, Generate then Reset | S3 | no | agent / agent or Ali |
| S7 | Finish twice, board record removed | S4, S5, S6 | no | agent / agent or Ali |
| S8 | Local gate smoke | S3 | yes | agent / Ali |

Why this differs from the suggested shape (seam, identifiers, target, CI, scenarios, gate): the
identifiers are not a subtask of their own. An identifier with no test is unverified dead
weight, and spread over S3 and S6 each lands with the test that uses it, in disjoint files.
The project-file edit (S2) is kept apart from the seam so the protected diff Ali reviews is
small; S0 comes first because three of five scenarios depend on one unverified gesture.

## Waves

- Wave 0: S0 (local).
- Wave 1: S1 || S2. Disjoint: `shared/src/ios*/.../uitest/**` vs the xcodeproj, one new test
  file and two protected skills.
- Wave 2: S3 || S4. Disjoint: app target, UI-test files, History Views and two reference skills
  vs `.github/workflows/ci.yml`.
- Wave 3: S5 || S6 || S8. Disjoint: one Details test file vs `UITests/Route/**` and
  `RouteView.swift` vs `scripts/**` and `tm-pr-workflow`. S5 and S6 both run the iOS gate
  steps; default cap of two concurrent subtasks (`epic-orchestration`), so S8 waits if the
  machine is busy.
- Wave 4: S7.

Hotspots: `iosApp/TrailMetrics.xcodeproj/**` only in S2. `iosApp/TrailMetrics/**` and
`iosApp/TrailMetricsUITests/Support/**` only in S3 (later scenarios read them, never edit them;
a missing helper goes into the scenario's own file). The `shared/.../uitest/` package in S1 and
S7, never in the same wave. `tm-pr-workflow/SKILL.md` in S2 and S8, different waves.

## Risks and what could go wrong

- **Map long-press not reachable** (F6): three scenarios blocked. S0 finds out before any PR.
- **CI simulator runtime below iOS 26.5**: the app cannot be installed on the CI simulator,
  though the generic build passes today. Not verified; S0 (5). Fix options are the human's
  (a newer runner image or Xcode selection in the workflow).
- **Maps key at launch:** CI has a placeholder key, so the map is blank and the SDK may log
  an authorization error; whether it shows a blocking alert or crashes is not verified (S0).
  With no key at all the app skips `configure`, and creating a `GMSMapView` may fail (not
  verified). Locally the real key loads map tiles during UI tests (network use, no assertion
  depends on it).
- **CI time:** +3 to 6 min estimated; measured in S4. If the full job nears 30 min, stop and
  report (Q4 alternative: a separate job).
- **Flakes:** XCUITest on a shared CI simulator; the package suite already had a timing flake
  (`RouteViewModelPendingEventsTests ... isDeliveredOnceToNextStreamOnly`). D5 and D6 apply;
  the risk remains and the policy is to report, not retry.
- **Finish-twice determinism:** location updates arrive at once; SwiftUI may coalesce
  `currentPath` changes so route progress jumps; S7 tunes the loop length to the progress
  search window (10) and checks 3 of 3.
- **Test code in the shipped framework** (F4, D1): the Kotlin fakes are in every build's
  XCFramework, unreachable without the DEBUG-only entry. Q1.
- **Probe overlay hides a control:** placed top centre; S3 checks no existing test target
  element is covered on the smallest simulator in use.
- **Unverified Koin override behavior:** S0 (3) and S1's tests.

## Questions for the human and his answers

1. **Seam (D1).** Kotlin fakes in `shared/src/iosMain/.../uitest/` shipped in the XCFramework
   like `SwiftTestSupport`, entered only through a `#if DEBUG` launch argument?
   Recommendation: yes. Other choice: a separate UI-test host target or configuration, about
   +1.5 min CI and a larger protected project diff, and still the same Kotlin binary.
   **Answer:** Yes. Kotlin fakes in the XCFramework, entered only through the `#if DEBUG`
   launch argument. They are not kept out of Release builds now (see Q9).
2. **Project file (D2).** The agent hand-edits `project.pbxproj` and the scheme; you review and
   merge. Recommendation: yes, with you creating the target in Xcode only if the edit fails.
   Other choice: you create the empty target first (a few minutes of your time, one more
   hand-off).
   **Answer:** Yes. The agent edits `project.pbxproj` and the scheme; Ali creates the empty
   target in Xcode only if the edit fails within the retry budget.
3. **Only if S0 shows the map long-press fails:** add a UI-test-only way to add waypoints in
   `RouteView` (product code, DEBUG only), or keep Generate twice, Generate then Reset and
   Finish twice on unit tests plus a human check. Recommendation: the DEBUG-only seam; the
   other choice leaves three of five scenarios unproven by UI tests.
   **Answer:** Not needed unless S0 shows the map long-press fails. If it does, the agent
   stops and reports; Ali decides then (recommendation of the plan stays: a DEBUG-only seam).
4. **CI placement (D3).** A step in the existing iOS job (no new required check, no
   branch-protection change). Recommendation: yes. Other choice: a separate job, which needs a
   new required status check in branch protection (your setting) and a second simulator boot.
   **Answer:** Yes. A step in the existing iOS job; no new required check.
5. **Flake policy (D6).** No automatic retries. Recommendation: yes. Other choice:
   `-retry-tests-on-failure -test-iterations 2` would hide real races in exactly the behavior
   these tests exist to catch.
   **Answer:** Yes. No automatic test retries.
6. **Gate trigger (D4).** Smoke only for `IOS_UI_PATHS`. Recommendation: yes. Other choice:
   whenever the iOS steps run (simpler, about 1.5 to 3 min more on every domain or data
   change).
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
   configuration (F4), so a Release app already contains Kotlin debug code and the UI-test
   fakes would be in it too, unreachable.
   **Answer:** not fixed in this epic. A separate BOARD.md record,
   `release-build-links-debug-xcframework`, covers a Release XCFramework before any
   distribution build.

## Done (record test-ios-ui-double-tap-and-stale-results)

Checked against its Done when: "a UI-test target exists in the shared scheme" (S2) "with a
launch-time fake seam" (S1, S3), "and XCUITest scenarios cover" Finish twice (S7), Generate
then Reset (S6), Generate twice (S6), delete confirmation twice (S5), failed delete (S3).
This plan also requires them to run in CI (S4), because a test that nothing runs proves
nothing; S7 depends on S4 for that reason. S8 is `agentic-dev-loop` item (1)'s local-gate
part, not part of this record.

## Epic-level Tier 2

- All five scenarios green in CI's iOS job on `main` after S7, on the CI simulator.
- Nothing needs a human on a device for these five behaviors. What stays manual is unchanged
  and outside this plan: the map's drawn route and markers, real GPS, permission dialogs, the
  Live Activity and notifications (`agentic-dev-loop` item (6)), checked before releases.
- No final smoke check: no user-visible behavior changes.
