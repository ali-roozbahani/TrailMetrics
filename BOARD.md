# Board

The backlog of open epics, tasks and drift, so follow-ups are not lost between PRs. It is
not a plan or a status tracker: if a record exists, the item is open. Records are only added,
deleted, narrowed when partly done, or given a new Order to make room for an insertion. They
never move between sections.

Sections are by type: **Epics** (multi-PR, plan under `docs/epics/`), **Tasks** (one PR),
**Drift** (docs/skills/comments that disagree with the code, found but not fixed). Each
record is a `### <slug>` heading (kebab-case, unique, descriptive, never a counter) followed by
these fields, in order: Type (epic | task | drift), Area, Order, After (optional), Source,
Problem, Done when, Refs.

- **Order** is an integer, unique across the whole file. Ascending Order is the execution
  order across all three sections (lowest first). New values use gaps of 10 so a record can
  be inserted between two others. Within each section, records are sorted by Order.
- **After** lists the slugs (comma-separated) that must be gone from the board before this
  record may start. Each must exist, have a lower Order, and not form a cycle.
- Order does not replace planning: an epic still needs a human-approved plan under
  `docs/epics/` before any work starts.

`scripts/check-board.sh` checks this format (it runs first in `scripts/pre-push-check.sh` and
in CI); `scripts/check-board.sh --next` prints the record to take next. Rules for adding and
deleting records: the "Board" section of `.claude/skills/tm-pr-workflow/SKILL.md`.

## Epics

### route-completion-to-domain
- Type: epic
- Area: domain, iosApp/Tracking, androidApp/feature-tracking
- Order: 60
- Source: audit + chat 2026-10-01
- Problem: Route-completion detection is written once per platform: on iOS inside `TrackingView` (`isRouteCompleted`, `routeCompletionIndexMargin`, `routeCompletionThresholdMeters`, its own `routeProgress`/`lastProgressIndex` state), on Android in `feature-tracking`'s `RouteCompletionTracker`. Neither is in `domain`, so the platforms can diverge. `calculateRouteProgress` in domain has no guard for out-of-range input: a `previousIndex` past the last point gives an empty search range and `subList` throws, and a negative `previousIndex` indexes out of bounds.
- Done when: completion logic lives in `domain` with `kotlin.test` coverage, both platforms call it, `TrackingView` only renders, `calculateRouteProgress` handles out-of-range `previousIndex` (and `searchWindow`) without throwing, and a human-approved plan exists under `docs/epics/`.
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/TrackingView.swift` (`isRouteCompleted`, `updateRouteProgress`); `androidApp/feature-tracking` `RouteCompletionTracker`; `domain` `RouteProgress` / `calculateRouteProgress`; `epic-orchestration` skill.

### figma-design-system
- Type: epic
- Area: design
- Order: 900
- Source: chat 2026-10-01
- Problem: There is no design system and there are no screens in Figma. The goal is tokens and screens in Figma that agents read through the Figma MCP to implement UI. This is deliberately the LAST item on the board: start it only after everything else.
- Done when: a token-based design system and the main screens exist in Figma, and an agent can implement a screen from them on both platforms.
- Refs: `androidApp/core-ui`, `iosApp/Packages/DesignSystem`; Figma MCP.

## Tasks

### app-kover-floor
- Type: task
- Area: androidApp
- Order: 25
- Source: PR offer-saved-session-at-app-start
- Problem: `androidApp/app` has unit tests now (20, line coverage 42.9% measured 2026-10-25) but no `koverVerify` minimum: a floor needs an entry in `config/kover-floors.properties` and the module's Kover block reading it, and the build file was authorized for the test source set and its comment only.
- Done when: `config/kover-floors.properties` has an `app` entry a little below the measured coverage (1 to 2 points, rounded down), `androidApp/app/build.gradle.kts` reads it like `androidApp/feature-tracking/build.gradle.kts`, `koverVerify` fails when the entry is set 1 point above the measured value, and the build file's Kover comment no longer says there is no floor.
- Refs: `androidApp/app/build.gradle.kts`; `config/kover-floors.properties`; `tm-pr-workflow` (Coverage ratchet).

### inject-dispatchers-from-di
- Type: task
- Area: androidApp/feature-tracking, data
- Order: 40
- Source: PR for tm-robustness-skill
- Problem: Seven places name a dispatcher themselves, which `tm-robustness` D1 forbids (neither a DI module nor the application root): `TrackingService` builds `CoroutineScope(SupervisorJob() + Dispatchers.Default)`, and `TrackingViewModel`, `UserProfileRepositoryImpl` and `ActivityHistoryRepositoryImpl` default a constructor parameter to `Dispatchers.IO`, and `DatabaseBuilder.kt` calls `setQueryCoroutineContext(Dispatchers.IO)`; the PR that moved the map snapshot save off the main thread added two more `Dispatchers.IO` defaults, the `ioDispatcher` parameter of `saveSnapshotToFile` (`util/MapSnapshotSaver.kt`) and the `snapshotDispatcher` parameter of `TrackingRoot` (`TrackingScreen.kt`). Moving the names into the Koin modules changes constructors and their tests across three modules, a different subject from the skill text.
- Done when: only DI modules and the application root name `Dispatchers.*`; the seven places receive their dispatcher or scope from Koin (the database builder gets its query context passed in; `TrackingRoot` gets the snapshot dispatcher and passes it to `saveSnapshotToFile`); existing tests pass a test dispatcher.
- Refs: `data/src/androidMain/.../tracking/TrackingService.kt`; `androidApp/feature-tracking/.../TrackingViewModel.kt`; `data/src/commonMain/.../user/UserProfileRepositoryImpl.kt`, `.../local/repository/ActivityHistoryRepositoryImpl.kt`; `data/src/commonMain/.../local/database/DatabaseBuilder.kt`; `androidApp/feature-tracking/.../util/MapSnapshotSaver.kt` (`saveSnapshotToFile`); `androidApp/feature-tracking/.../TrackingScreen.kt` (`TrackingRoot`'s `snapshotDispatcher`); `tm-robustness` D1.

### strictmode-leak-detection-debug
- Type: task
- Area: androidApp/app
- Order: 45
- Source: PR for tm-robustness-skill
- Problem: The app has no `StrictMode` policy (thread or VM) and no LeakCanary, so a blocking call on the main thread or a leaked `Activity` or closable is only found by reading (`tm-robustness` C1, M8). LeakCanary is a third-party dependency, so it needs the human's decision; the `StrictMode` policies need none.
- Done when: a debug-only `StrictMode` thread policy and VM policy (`detectLeakedClosableObjects`, `detectActivityLeaks`, penalty log or death) are set in `TrailMetricsApplication`, or LeakCanary is added by name in a task that approves it, and `tm-robustness` M8 names which one exists.
- Refs: `androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/TrailMetricsApplication.kt`; `tm-robustness` M8.

### enable-robustness-lint-rules
- Type: task
- Area: config, scripts
- Order: 50
- Source: PR for tm-robustness-skill
- Problem: Rules that would check `tm-robustness` mechanically are not enabled. Measured with scratch configs (production code, this repo): detekt `InjectDispatcher`, `UnsafeCast`, `SleepInsteadOfDelay` and `RedundantSuspendModifier` are on by default but need type resolution, and the gate runs plain `detekt`, so they never fire (`InjectDispatcher` gives 1 hit with `detektAndroidMain`, in `TrackingService`; only `data` and `shared` were run typed). Off by default and giving 0 hits: `GlobalCoroutineUsage`, `SuspendFunSwallowedCancellation`, `LateinitUsage`, `CastToNullableType`, `ThrowingExceptionInMain`, `NotImplementedDeclaration`; 1 hit: `ElseCaseInsteadOfExhaustiveWhen` (in `TrackingService.buildNotification`); `LabeledExpression` 9, `CognitiveComplexMethod` 4. SwiftLint opt-in rules with 0 hits: `weak_delegate`, `discarded_notification_center_observer`, `unhandled_throwing_task`, `unowned_variable_capture`, `implicitly_unwrapped_optional`; `async_without_await` 1. Android lint with all checks on gave nothing about threads or leaks. Config and gate files are protected, so a human decides.
- Done when: the 0-hit rules above are enabled, the typed detekt tasks (`detektAndroidMain` for the KMP modules) run in the gate and CI, the 1-hit ones are fixed or declined with a reason, and `tm-robustness`' "Enforced" lines name the new rules.
- Refs: `config/detekt/detekt.yml`; `iosApp/.swiftlint.yml`; `scripts/pre-push-check.sh`; `.github/workflows/ci.yml`; `tm-robustness` ("Mechanical rules").

### tracking-viewmodel-snapshot-file-access
- Type: task
- Area: androidApp/feature-tracking
- Order: 51
- Source: PR for tm-robustness-cleanup
- Problem: Android `TrackingViewModel` deletes snapshot files itself (`deleteSnapshotFile`, `fileScope`, `File(path).delete()`), a ViewModel touching a file, which the Architecture rules of `tm-android` mark `blocking`. Moving it behind a `domain` interface changes constructors, Koin wiring and tests, so it is not fixed in a skills PR.
- Done when: the ViewModel has no `java.io` use and no file scope; the deletion sits behind an interface (a domain use case or a data class) that the ViewModel receives, with its test.
- Refs: `androidApp/feature-tracking/.../TrackingViewModel.kt` (`deleteSnapshotFile`, `fileScope`); `tm-android` Architecture; `tm-robustness` D3.

### ios-launcher-depends-on-concrete-location-repository
- Type: task
- Area: data, domain
- Order: 52
- Source: PR for tm-robustness-cleanup
- Problem: `IosTrackingServiceLauncher` takes the concrete `IosLocationRepositoryImpl`, not a `domain` interface, because `setBackgroundUpdatesEnabled` is not on `LocationRepository`; `tm-kmp-shared` ("Module boundaries") marks a class that takes the implementing class `blocking`. Adding a method to the interface or a new one changes domain, both platforms' fakes and the Koin module, so it needs a decision on the interface shape.
- Done when: `IosTrackingServiceLauncher` receives a domain interface only, the Koin module passes that, and a test covers the launcher with a fake.
- Refs: `data/src/iosMain/.../tracking/IosTrackingServiceLauncher.kt`; `data/src/iosMain/.../di/IosLocationModule.kt`; `data/src/iosMain/.../location/IosLocationRepositoryImpl.kt`; `tm-kmp-shared` ("Module boundaries").

### tracking-metrics-calories-to-domain
- Type: task
- Area: domain, iosApp/Tracking, androidApp/feature-tracking
- Order: 53
- Source: PR for tm-robustness-cleanup
- Problem: The metrics extraction from `TrackingState` and the calorie recompute are hand-written in both `TrackingViewModel`s (Android's and iOS `TrackingViewModel.swift`: `currentMetrics`, `recomputeCalories`); `tm-kmp-shared` ("Where logic lives") puts derived state both platforms need in `domain`. Moving it changes both ViewModels and adds a use case with tests, so it is a task of its own.
- Done when: one pure function or use case in `domain` with `kotlin.test` coverage computes them, and both ViewModels only adapt it.
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/TrackingViewModel.swift` (`currentMetrics`, `recomputeCalories`); `androidApp/feature-tracking/.../TrackingViewModel.kt`; `tm-kmp-shared` ("Where logic lives").

### history-details-snapshot-delete-on-main
- Type: task
- Area: androidApp/feature-history
- Order: 54
- Source: PR for tm-robustness-cleanup
- Problem: `HistoryViewModel.deleteActivity` and `DetailsViewModel.deleteActivity` call `deleteSnapshotFile` (`File(path).delete()`) inside `viewModelScope.launch`, which runs on the main thread after the repository call returns; `tm-robustness` C1 and D3 make that a blocking violation. The fix changes constructors and tests of two ViewModels, so it is a task of its own.
- Done when: the file delete runs off the main thread (or behind the same interface as `tracking-viewmodel-snapshot-file-access`), with the failure path tested.
- Refs: `androidApp/feature-history/.../HistoryViewModel.kt`, `.../DetailsViewModel.kt`, `.../util/SnapshotFileDeleter.kt`; `tm-robustness` C1, D3.

### ios-live-activity-ticker
- Type: task
- Area: iosApp/Tracking
- Order: 70
- After: route-completion-to-domain
- Source: PR #66 review
- Problem: The Live Activity's elapsed time is a static `elapsedMillis` value. It changes only when a tracking-state emission (driven by location events) reaches `TrackingLiveActivityController.update`, which is also throttled to one update per second. Without location events it freezes, then jumps.
- Done when: the elapsed time uses a system timer anchored to a start date and advances without updates (metrics may still depend on updates). Verified on a real device; the simulator does not suspend like a device.
- Refs: `TrackingLiveActivityController.update` / `minimumUpdateInterval`; `TrackingActivityAttributes.ContentState.elapsedMillis`; `iosApp/TrackingWidget/TrackingLiveActivity.swift` `formatElapsed`.

### tracking-ui-timer-independent-of-location
- Type: task
- Area: domain, iosApp, androidApp
- Order: 80
- After: route-completion-to-domain
- Source: PR #66 test
- Problem: The in-app elapsed time shows `metrics.elapsedMillis` from the tracking state, which is only re-emitted on location events. There is no ticker, so a stationary device freezes the timer and the display can jump (observed by 2 s).
- Done when: the displayed time ticks independently of location events on both platforms, without changing the domain's accounting of elapsed time.
- Refs: `TrackingSessionManager` (state emissions); Android `TrackingScreen` (`formatElapsedTime(metrics.elapsedMillis)`); iOS `MetricsDisplay`.

### android-ui-test-launch-seam
- Type: task
- Area: androidApp
- Order: 90
- Source: PR #210 and chat 2026-10-23
- Problem: Android has no launch-time seam (fakes for location, directions and storage injectable when the app starts, as iOS has with `UITEST_SEAM`) and no app-level UI-test target; its UI tests are Robolectric tests per screen, so a flow across screens with the app's real navigation and Koin graph is not covered by any test. Recorded because the deleted `agentic-dev-loop` epic's Done when (1) was read as Robolectric tests only; it is a different subject from the PR that found it.
- Done when: such a seam and a UI-test target exist on Android, and at least one flow across two screens runs in CI and fails when a binding or a navigation is broken (shown on a deliberately broken version). The design (instrumented test or Robolectric with the real graph) is stated in the PR and fits the `shared` Koin graph tests of #207.
- Refs: `docs/epics/agentic-dev-loop.md` (Done when item 1, deleted record); `docs/epics/ios-ui-tests.md`; `.claude/skills/tm-testing`; `shared-uitest`.

### release-build-links-debug-xcframework
- Type: task
- Area: iosApp, shared
- Order: 105
- Source: docs/epics/ios-ui-tests.md Q9 (PR #138), 2026-10-13
- Problem: `iosApp/Packages/SharedKit/Package.swift` points its `binaryTarget` at `shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework` for every build configuration, and `scripts/build-kmp-framework.sh` builds only the debug XCFramework (`:shared:assembleTrailMetricsSharedDebugXCFramework`). So a Release build of the app links the debug Kotlin framework. That framework no longer contains the Swift test support or the iOS UI-test fakes: both live in `shared-uitest`, which is built only into a test-only variant of the framework (`docs/epics/ios-ui-tests.md`, D1), and `scripts/check-production-framework.sh` checks that the production framework has none of it. What remains is that the Release build links a debug-configuration framework.
- Done when: a Release app build links a release XCFramework that contains no test-support or UI-test code, shown by a command in the PR (for example a symbol check on the Release app binary), and the gate and CI still build and test with the debug XCFramework.
- Refs: `iosApp/Packages/SharedKit/Package.swift`; `scripts/build-kmp-framework.sh`; `shared/build.gradle.kts` (`binaries.framework`); `shared-uitest/src/iosMain/kotlin/dev/roozbahani/trailmetrics/uitest/testsupport/SwiftTestSupport.kt`; `scripts/check-production-framework.sh`; `docs/epics/ios-ui-tests.md` (F4, D1, Q9); `.claude/skills/tm-ios/SKILL.md` ("Build integration").

### tracking-location-path-double-clock-read
- Type: task
- Area: domain
- Order: 140
- Source: PR #66 drift
- Problem: In `TrackingSessionManager.observeLocation`, each `LocationUpdate.Success` reads `clock.elapsedRealtimeMillis()` twice: once for `speedCalculator.calculate` and once for `TrackingEvent.LocationReceived`. Speed and accounting can therefore see slightly different timestamps for the same event.
- Done when: the clock is read once per event and reused, with a test.
- Refs: `domain` `TrackingSessionManager.observeLocation`, `SpeedCalculator`.

### polyline-decoder-invalid-characters
- Type: task
- Area: data
- Order: 160
- Source: PR #68 review
- Problem: `decodePolyline` rejects only truncated input. Characters outside the valid encoded-polyline range (`?`..`~`) are not rejected: `code - 63` is used as-is and silently decodes to garbage coordinates instead of failing.
- Done when: invalid characters throw `IllegalArgumentException` (which `DirectionsRepositoryImpl` already maps to `DirectionsApiError`), with tests.
- Refs: `data` `decodePolyline` / `decodeValue`; `PolylineDecoderTest`; `DirectionsRepositoryImpl.getClosedRoute`.

### test-data-remaining-untested-classes
- Type: task
- Area: data
- Order: 170
- Source: PR #70
- Problem: After the directions tests, `data` is at 44.38% line coverage (142/320, Android host Kover report, generated code excluded). The five biggest gaps (uncovered lines, nested/lambda classes merged into their source class) all have 0% covered: `AndroidLocationRepositoryImpl` (49), `TrackingService` (44), `di/CommonTrackingModule` (14), `di/NetworkModule` (10), `di/UseCaseModule` (10). iOS-only code (`IosLocationRepositoryImpl`, `IosTrackingServiceLauncher`) isn't in the report at all, because Kover can't measure the iOS run.
- Done when: those classes have tests (or a documented reason why one can't be tested on the host), and the `data` Kover floor is raised in the same PR.
- Refs: `data` `location/AndroidLocationRepositoryImpl`, `tracking/TrackingService`, `di/CommonTrackingModule`, `di/NetworkModule`, `di/UseCaseModule`; `data/build.gradle.kts` `kover.reports.verify`; `tm-testing`.

### android-tracking-notification-content
- Type: task
- Area: data
- Order: 190
- Source: PR #66 test
- Problem: The Android foreground tracking notification (built in `data`'s androidMain `TrackingService.buildNotification`) shows only "Tracking..."/"Paused - " plus distance. It has no elapsed time or other metrics. No doc or skill records whether that is intentional.
- Done when: it shows elapsed time and key metrics, or the decision not to is documented.
- Refs: `data/src/androidMain` `TrackingService.buildNotification`.

### swiftlint-disable-requires-reason-rule
- Type: task
- Area: iosApp
- Order: 194
- Source: agentic-dev-loop run 18 review (PR #104), 2026-10-05
- Problem: the repo's convention is `// swiftlint:disable:next <rule> - <reason>`, but a disable comment with no reason, or with an empty one (` - ` and nothing after it), still passes `--strict` (seen with SwiftLint 0.65.1 on a fixture: exit 0, 0 violations); only review notices.
- Done when: a check rejects a `swiftlint:disable` comment (any rule, `:next`, `:this`, `:previous` and the block forms) that has no ` - <reason>` text, every existing suppression under `iosApp/` complies or the PR lists the ones that do not with the human's decision, and the check is shown failing on an example without a reason and passing with one (a SwiftLint custom rule on comments, or a small script, whichever the PR justifies).
- Refs: `iosApp/.swiftlint.yml`; `tm-ios` ("SwiftLint", suppression convention).

### wait-until-cancellation-spin
- Type: task
- Area: iosApp/TestSupport
- Order: 196
- Source: agentic-dev-loop run 18 review (PR #104), 2026-10-05
- Problem: `waitUntil` in TestSupport polls with `try? await Task.sleep(for: .milliseconds(10))`; when the calling test task is cancelled, `Task.sleep` throws at once and the `try?` drops that, so the loop spins without any delay until its deadline (up to 120 seconds, `coldStartTimeout`, for the first wait in a test process). No failure is hidden, but the test burns CPU instead of stopping. The `optional_try` annotation on that line says only that the deadline still ends the wait.
- Done when: `waitUntil` stops promptly when its task is cancelled (for example it checks `Task.isCancelled` or lets the cancellation error end the wait), a test shows it (red before, green after), and the `swiftlint:disable:next optional_try` comment is updated or removed to match the code.
- Refs: `iosApp/Packages/TestSupport/Sources/TestSupport/Support/WaitUntil.swift`; PR #104.

### selftest-scratch-repo-hardening-other-scripts
- Type: task
- Area: scripts
- Order: 197
- Source: fix of the skill rule-change self-test cleanup PR, 2026-10-06
- Problem: `check-kover-floors.py`, `check-protected-paths.py` and `classify-changes.sh` build scratch git repositories and commit in them without `gc.auto=0` and `maintenance.auto=false`, and remove them with a bare `tempfile.TemporaryDirectory` or `rm -rf`; `check-ios-scope.py` has `gc.auto=0` but not `maintenance.auto=false`. The same "Directory not empty" failure that once stopped the skill rule-change self-test in CI could hit any of them.
- Done when: each gets the same git flags and the same resilient cleanup as `check-skill-rule-changes.py` (or one shared approach the human agrees), with its self-test still passing.
- Refs: `scripts/check-kover-floors.py`; `scripts/check-protected-paths.py`; `scripts/classify-changes.sh`; `scripts/check-ios-scope.py`; `scripts/check-skill-rule-changes.py` (`remove_scratch`).

### build-kmp-framework-self-test
- Type: task
- Area: scripts
- Order: 201
- Source: chore/script-self-tests scan for scripts without a `--self-test`, 2026-10-22
- Problem: `scripts/build-kmp-framework.sh` decides by an input hash and a variant marker whether to rebuild the XCFramework, and fails an Xcode `--build-phase` call after a rebuild instead of linking a stale copy. None of this has a self-test, so a regression in the hash gating, the variant switch or the `--build-phase` exit would show up only as a stale framework in an iOS build. A self-test needs the Gradle call stubbed (a fake `gradlew` in a scratch tree), which is a design choice of its own.
- Done when: a `--self-test` runs the script in a scratch tree with a fake `gradlew` and checks: a first build runs Gradle, an unchanged second run skips it, a changed input or the other variant rebuilds, `--build-phase` after a rebuild exits non-zero with the message, an unknown option and an unknown variant exit 2; it passes on bash 3.2 and bash 5 (or `sh`, per the script's shebang), and is wired into the gate, CI's `tooling` job and CODEOWNERS like the other self-tests; it was shown failing against a deliberately broken version.
- Refs: `scripts/build-kmp-framework.sh`; `scripts/pre-push-check.sh`; `.github/workflows/ci.yml`; `.github/CODEOWNERS`.

### simulate-route-self-test
- Type: task
- Area: scripts
- Order: 202
- Source: chore/script-self-tests scan for scripts without a `--self-test`, 2026-10-22
- Problem: `scripts/simulate-route.sh` (the developer tool that walks an iOS Simulator along a route through `xcrun simctl location`) interpolates points between waypoints and paces them to a speed, and has no self-test, so a regression in the interpolation, the pacing or the CSV parsing would show only as a wrong walk in a simulator. It needs `xcrun`, so a test must put a fake `xcrun` first on `PATH`.
- Done when: a `--self-test` runs the script against a fake `xcrun` that records its calls and a short CSV in a `*-fixtures/` folder, and checks the interpolated points, the pace, the loop back to the first waypoint (the run bounded by the fake) and the errors for a missing or malformed file; it passes on bash 3.2 and bash 5, is wired into the gate and CODEOWNERS (CI's `tooling` job has no simulator but needs none), and was shown failing against a deliberately broken version.
- Refs: `scripts/simulate-route.sh`; `scripts/routes/sample-loop.csv`; `scripts/pre-push-check.sh`; `.github/CODEOWNERS`.

### flake-ios-ui-route-map-press-lost
- Type: task
- Area: iosApp/TrailMetricsUITests
- Order: 220
- Source: CI run 39049148407 (main, push, head 46a3636, the merge of #161), 2026-10-17; escalated at count 3 from the entry `ios-ui-route-map-press-lost` in `CI_FLAKES.md`
- Problem: `iOS — run UI tests` (since renamed `iOS 3 — run UI tests (after 2a)`) failed (exit 65) twice on `main`, in two Route tests, with the same message "Generate button not enabled after 3 waypoints" (the 10 s wait for `isEnabled` timed out in the same `XCTAssertEqual` of `XCUIApplication+RouteMap.swift`): `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce` (run 39049148407: test about 160 s, step about 802 s) and `RouteGenerateThenResetUITests.test_resetWhileGenerating_leavesACleanScreen` (run 39074545852: test about 92 s, step 510 s); the other five tests passed in both. #161 changed only comments in `scripts/classify-changes.sh` and `scripts/pre-push-check.sh` and one fixture `expect` line, and #162 only two skills and the epic text; none is an input of the iOS jobs. The cause is unknown. A slow runner or map is a hypothesis that the timings support but do not prove: in the first run the `route.map` check took about 77 s and the map presses 3 to 12 s; in the second the check took about 1 s and one of three presses took about 39 s (the others 8 and 4 s). The first suite started 302 s and 195 s after `xcodebuild` in the two failed runs and 126 to 357 s in the ten executions of the last 100 runs of `ci.yml`, so a late start does not tell failing runs from passing ones. In those 100 runs the job ran its tests 10 times (6 on `main`, 4 on PR branches, all four green; 5 more were skipped or cancelled) and failed 2, both on `main`, both Route tests; the step took 370 to 802 s; 3 of the 60 test executions took over 100 s (143 s `deleteConfirmedTwice`, 135 s `resetWhileGenerating`, 160 s the first failure). Before the split the same step ran 23 times in the single iOS job; one of those failed after 72 s (2026-10-14, not investigated). The two result bundles show that at the failure the screen had no red waypoint marker and Generate was disabled, so fewer than 3 waypoints existed; which press was lost, and why, is unknown. The log has no `GMS`, network or tile line. The location-permission alert appears in `RouteGenerateThenResetUITests` in every run (it is the first Route test), so it is not the cause by itself. The helper `addRouteWaypoints` reported any press problem as "Generate button not enabled"; since the change `test(ios-ui): make the Route map-press failures say which press was lost` it reports the press (k of N), the waypoint count the app showed, the press timings and a screenshot, so the next red run will say which press was lost. Risk noted: the Route tests depend on the location-permission state left by an earlier test (the tests run alphabetically and the alert appears only in the first Route test). A third failure came with run 39137921296 (the push of the #167 merge to `main`): `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce` failed with "map press 1 of 3 did not add a waypoint: count 0, expected 1 (press took 12.55 s, 23.50 s since the helper began)". The earlier two failures had no per-press diagnostic, so it is unproven that they were press 1. The result bundle of the third failure shows the map blank with no tiles, no permission alert or other overlay, the green start pin, no red waypoint marker, the probe overlay reading `waypoints=0` after two refreshes (so the app was responsive), Generate visible and disabled, and the press point clear of every overlay. The log shows the app launch to the automation session taking 56.5 s (29 s in the first test of that run) and the synthesized press event taking about 8 s; there is no XCUITest error, no interrupting element and no Maps, network or tile line. Counts: 2 failures in the 11 executions that ran tests before the diagnostics and 1 failure in the 4 executions after them (1 lost press in 12 helper calls). Press durations of passing helper calls range from about 1.6 s to 42 s, so a slow press alone does not separate failing from passing. Hypotheses: a load-related loss of the press is probable, not proven (there is no app-side evidence that the event reached the map); that the map's gesture handling was not ready although `route.map` exists is unknown (there is no app-side signal); that `didLongPressAt` is a no-op in some state is not supported by the code (it has no state guard); an alert or overlay is ruled out for this execution. The "use your location?" system alert appears once per execution and is dismissed by the default interruption handler; its origin was not found (UI-test mode replaces the location repository by a fake). The change `test(ios-ui): add Route waypoints through a seam, keep one map long-press test` makes three tests (`RouteGenerateTwiceUITests`, `RouteGenerateThenResetUITests`, `TrackingFinishTwiceUITests`) add their waypoints through the probe's seam button and keeps one test, `RouteMapLongPressUITests`, on the real long press: the dependency of the other three on the press is gone, the press path itself is not fixed, and the cause stays unknown. Two later red runs were app launch timeouts in the first Details tests, not this flake (in the last 100 runs of `ci.yml` the UI-test job ran its tests 36 times: 31 green, 5 red, 3 of them this Route flake and 2 launch timeouts); they are the entry `ios-ui-details-launch-timeout` in `CI_FLAKES.md`.
- Done when: the flake no longer fails or the runner/test is changed so it cannot, shown on 5 consecutive runs of the iOS UI-test job.
- Refs: CI runs 39049148407 and 39074545852; `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce`; `RouteGenerateThenResetUITests.test_resetWhileGenerating_leavesACleanScreen`; CI run 39137921296; `RouteMapLongPressUITests.test_longPress_addsAWaypoint`; `iosApp/TrailMetricsUITests/Route/XCUIApplication+RouteMap.swift`; `docs/epics/ios-ui-tests.md` (D6); `.claude/skills/tm-testing/SKILL.md` ("Flakes (D6)"); `CI_FLAKES.md`.

### ios-ui-location-permission-alert-origin
- Type: task
- Area: iosApp/TrailMetricsUITests
- Order: 225
- Source: board record flake-ios-ui-route-map-press-lost and chat 2026-10-18
- Problem: The "use your location?" system alert has so far been seen only in CI logs or result bundles, not locally. A local look found no origin: the production `IosLocationRepositoryImpl` is ruled out (the UI-test module overrides all five bindings that would create it, and `UiTestEntryTest` asserts it is never created in UI-test mode), no Swift file requests location, and on a fresh local simulator (iPhone 17, iOS 26.5, privacy reset, app uninstalled) the alert did not appear in `RouteGenerateTwiceUITests` alone or in the three Route classes run in order; a temporary interruption monitor never fired. The Route tests may still depend on the permission state an earlier test left. The CI logs read since then show the alert in every UI-test log (red and green), only in `RouteGenerateThenResetUITests`, the first Route test, about 9 to 10 s into the test, and the default interruption handler dismisses it with "Don't Allow". It does not appear in the Details tests that run before it, so something in the Route screen's start triggers it; the origin is still not found.
- Done when: the alert is captured on CI (an interruption monitor in the Route tests that records its label, or a failing run's result bundle), and the Route tests no longer depend on which ran first, either by `XCUIApplication.resetAuthorizationStatus(for: .location)` before launch or by handling the alert explicitly in each Route test. If CI's simulator itself needs a reset step, that touches the protected CI workflow and the human decides.
- Refs: `RouteGenerateThenResetUITests` and the other Route tests; `iosApp/TrailMetricsUITests/Route/XCUIApplication+RouteMap.swift`.

### shared-metrics-formatter-user-visible-strings
- Type: task
- Area: shared, iosApp
- Order: 226
- Source: PR for ios-localizable-strings
- Problem: `domain/.../util/MetricsFormatter.kt` (`formatDistance`, `formatSpeed`, `formatCalories`) returns finished user-visible texts with the unit words and the "no value" placeholder inside the Kotlin string ("1.50 km", "-- km/h", "-- kcal"). iOS shows them verbatim (`Text(value)` in `HistoryMetricCell`, `TrackingMetricCell`), so they cannot come from a String Catalog and a translation of the unit words is impossible on iOS. Android uses the same functions. Left alone in the localization PR because the fix needs a design decision: return the number and unit as values and let each platform format them, or pass localized unit labels in.
- Done when: the decision is made (an ADR or a plan if it changes the shared API), and iOS and Android both show these values from their own localizable resources; the iOS catalogs carry the unit and placeholder texts.
- Refs: `domain/src/commonMain/kotlin/dev/roozbahani/trailmetrics/domain/util/MetricsFormatter.kt`; `iosApp/Packages/*/Sources` (`formatDistance` callers); `ios-hardcoded-number-formatting`.

### ios-hardcoded-number-formatting
- Type: task
- Area: iosApp, shared
- Order: 227
- After: shared-metrics-formatter-user-visible-strings
- Source: PR for ios-localizable-strings
- Problem: Number and unit formatting is hardcoded and ignores the user's locale: the Live Activity (`TrackingWidget/TrackingLiveActivity.swift`) re-implements the shared formatter in Swift with `String(format: "%.2f km")`, `"%.1f km/h"`, `"\(Int(meters)) m"`, `"-- km/h"` and a fixed `%02d:%02d`; the Kotlin `formatFixed` always writes a `.` as the decimal separator. A comma-decimal locale, or miles for a user who expects them, gets the English-US shape. Dates are not affected: `ActivityRow.dateFormatter` uses `DateFormatter` with `.medium`, which follows the locale. Found, not fixed, in the localization PR (formatting is a separate topic).
- Done when: distances, speeds, calories and durations on iOS (app and widget) are formatted with the user's locale (`Measurement`/`FormatStyle`, or values formatted by the platform), or the decision to keep metric units fixed is recorded; the widget no longer duplicates the shared formatter by hand.
- Refs: `iosApp/TrackingWidget/TrackingLiveActivity.swift` (`formatDistance`, `formatSpeed`, `formatElapsed`); `domain/.../util/MetricsFormatter.kt` (`formatFixed`); `shared-metrics-formatter-user-visible-strings`.

### skill-folder-front-matter-detection
- Type: task
- Area: scripts
- Order: 231
- Source: PR for pr-review-item-3-reference-skill-files
- Problem: A change to the YAML front matter of a `SKILL.md` or reference file in the five ownerless skill folders (`tm-ios`, `tm-android`, `tm-kmp-shared`, `tm-testing`, `tm-robustness`) is escalated by `tm-pr-review` item 3 only because the reviewer reads the diff. No script detects it, so a missed read lets front matter (which can carry settings) change without a human.
- Done when: a script under `scripts/` with a self-test (in the gate and CI) reports a diff that changes the front matter of a Markdown file in those folders, and item 3 of `tm-pr-review` points to its output instead of asking the reviewer to read for it. Both are protected paths: a human PR.
- Refs: `.claude/skills/tm-pr-review/SKILL.md` (item 3); `scripts/check-protected-paths.py` (`UNOWNED_PATTERNS`); `scripts/check-skill-rule-changes.py`.

### tracking-location-update-path-cost
- Type: task
- Area: domain, data, androidApp/feature-tracking, iosApp/Tracking
- Order: 241
- Source: PR for tm-robustness-skill
- Problem: Every location update (every 3 s on Android, every callback on iOS with no `distanceFilter`) copies the whole path (`path + coordinates` in `UpdateTrackingStateUseCase`), emits a new state, and the Android polyline is rebuilt from the full list (`RoutePolyline`, `remember(points)`); nothing is conflated or sampled, and both platforms request the highest accuracy for the whole session. Cost grows with session length; the right sampling and accuracy are a product and battery decision.
- Done when: the path grows without a full copy per update (or is sampled by distance), the UI receives conflated updates, and the owner's accuracy and interval choice is recorded in `tm-robustness` P4 and P6.
- Refs: `domain/.../usecase/UpdateTrackingStateUseCase.kt`; `data/src/androidMain/.../location/AndroidLocationRepositoryImpl.kt`; `data/src/iosMain/.../location/IosLocationRepositoryImpl.kt`; `androidApp/core-ui/.../map/RoutePolyline.kt`; `tm-robustness` P4, P6.

### history-query-index-and-columns
- Type: task
- Area: data
- Order: 242
- Source: PR for tm-robustness-skill
- Problem: `tbl_activities` has no index on `startedAtEpochMillis`, which `ActivityDao.observeAll` sorts by, and the list query is `SELECT *`, so the history screen loads every row including both coordinate lists for the whole table (`tm-robustness` P5). An index is a Room schema change (`tm-kmp-shared`, "Changing the database schema") and a list projection changes the repository interface, so it is a task of its own.
- Done when: the sorted column has an index with its migration and test, and the history list reads only the columns it shows (or the cost is measured and accepted).
- Refs: `data/src/commonMain/.../local/entity/ActivityEntity.kt`; `.../local/dao/ActivityDao.kt`; `tm-robustness` P5.

### ios-snapshot-stored-at-full-resolution
- Type: task
- Area: iosApp/Tracking
- Order: 244
- Source: PR for snapshot-save-off-main-thread
- Problem: The iOS map snapshot is rendered at the map view's full bounds and screen scale and stored as that PNG (`renderMapSnapshot`, `writeMapSnapshot` in `MapSnapshotSaver.swift`), while Android scales to 600 px wide (`saveSnapshotToFile`). The stored file is several times larger on iOS (`tm-robustness` M5). Changing the stored size or format is a product decision about what the history screens show, so it is not made in the PR that moved the save off the main thread.
- Done when: the owner has decided the stored snapshot size, and iOS stores the same size as Android (or the difference is recorded as intended in `tm-ios`).
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/MapSnapshotSaver.swift`; `androidApp/feature-tracking/.../util/MapSnapshotSaver.kt`; `tm-robustness` M5.

### ios-snapshot-request-guard-test-seam
- Type: task
- Area: iosApp/Tracking
- Order: 245
- Source: PR for snapshot-save-off-main-thread
- Problem: The iOS Finish snapshot request in `TrackingMapView.updateUIView` has no test: the once-per-request guard (`handledSnapshotRequestID`), the task cancelled in `dismantleUIView`, and the dropped result for an old request run inside a `UIViewRepresentable` over a `GMSMapView`, which no package test can render or drive, and the iOS UI tests have no scenario that reaches the map snapshot. A seam is needed, for example the request handling moved into a small type that takes the render and the writer as closures, so a package test can call it. That is a design choice for the owner, so it is not made in the PR that moved the save off the main thread (`tm-pr-workflow` Tier 2, reason 2).
- Done when: the request handling (handle a request id once, cancel on teardown, drop a result whose request is no longer current, reset the request after delivery) is reachable from a Swift package test or a UI-test scenario, and tests cover each of the four.
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/TrackingMapView.swift`, `MapSnapshotSaver.swift`, `TrackingView.swift` (`finishTracking`); `tm-pr-workflow` Tier 2; `tm-testing`.

### gate-self-test-list-duplicates-ci-tooling
- Type: task
- Area: scripts, .github/workflows/ci.yml
- Order: 246
- Source: investigation of ten red `main` runs, 2026-10-25
- Problem: the self-tests are listed twice by hand: `scripts/pre-push-check.sh` (one `run_step` per script, from "protected paths" to "skill changes digest self-test") and the `tooling` job of `.github/workflows/ci.yml` (the steps from "Protected paths check" to "Skill changes digest self-test", plus the iOS ones at the `Localized strings rules self-test`, `Optional try rule self-test` and `Production framework check self-test` steps). A script added to one list and not the other runs only in the gate or only in CI; the new `main-ci-status.sh` self-test had to be added to both. Needs a human decision: one list (a script that runs every `*-fixtures` self-test) or a check that the two lists agree.
- Done when: one source names the self-tests, or `scripts/` has a check that fails when the gate and `ci.yml` disagree, with its own self-test.
- Refs: `scripts/pre-push-check.sh`; `.github/workflows/ci.yml`; `.github/CODEOWNERS`.

### flake-ios-ui-details-launch-timeout
- Type: task
- Area: iosApp/TrailMetricsUITests
- Order: 247
- Source: CI runs 39425719146 and 40122507751 (main, push); escalated at count 3 from the entry `ios-ui-details-launch-timeout` in `CI_FLAKES.md`
- Problem: `iOS 3 — run UI tests (after 2a)` failed on `main` with `DetailsDeleteTwiceUITests.test_deleteConfirmedTwice_deletesOnce` "Failed to launch" (73 s) in `XCUIApplication+Scenario.swift`, twice on pushes (2026-10-20, 2026-10-24) and once on a pull request; `DetailsFailedDeleteUITests` also failed to launch ("Failed to get background assertion") in the 2026-10-24 run. No test body ran. Later runs with the same tests were green. Cause not shown; the step boots the simulator with `simctl bootstatus -b` since #179 and the 2026-10-24 failure happened after it.
- Done when: the flake no longer fails or the runner/test is changed so it cannot, shown on 5 consecutive runs of the iOS UI-test job.
- Refs: CI runs 39425719146 and 40122507751; `iosApp/TrailMetricsUITests/Support/XCUIApplication+Scenario.swift`; `CI_FLAKES.md` entry `ios-ui-details-launch-timeout`.

### ios-tracking-finish-test-fixed-wait
- Type: task
- Area: iosApp/Packages/Tracking
- Order: 248
- Source: CI run 39459833673 (main, push, head fe41afd), 2026-10-20
- Problem: `iOS 2b` failed once in `TrackingViewModelFinishTests.test_onFinishClicked_afterFailedSave_savesAgain` ("Condition not met within 2.0 seconds", then "Expected showError, got []"). The code was unchanged and green on the next push. The cause is in our test: a fixed 2.0 s wait for the ViewModel on a loaded runner. #209 rewrote this file after the run, so the wait may already be gone; not checked.
- Done when: the tests in `TrackingViewModelFinishTests` wait on the state they assert without a fixed 2.0 s bound that depends on runner speed, or the record is deleted because #209 already did so.
- Refs: CI run 39459833673; `iosApp/Packages/Tracking/Tests/TrackingTests/TrackingViewModelFinishTests.swift`; `CI_FLAKES.md` entry `ios-tracking-finish-failed-save-wait`.

### local-review-hook-shell-blind-spots
- Type: task
- Area: scripts/claude-hooks
- Order: 250
- Source: PR for local-review-gate (owner decision: audit 61)
- Problem: `scripts/claude-hooks/require-local-review.sh` reads the command text, so it cannot see a push built by shell syntax it does not parse: `$'git'`, `\git`, a variable-built or `eval`ed command, a script the agent writes and runs, and a `cd` that may not run (`false && cd x; git push`, which the linear reading applies anyway). Other points the reviewers raised, left for audit 61 by the owner: `.claude/settings.json` itself is not guarded against edits by the hook (a guard would block the owner's own protected tasks, so it is left to the owner); any command containing the word `local-reviews` or a `cd`/`pushd`/`popd` token before a push (a branch named `cd`) blocks even when harmless. A separate mechanism than command-text matching (for example the credential helper or a `pre-push` check the human installs) is the only complete fix; this is a human design decision.
- Done when: the owner has decided in audit 61 which of these to close and how (a stronger mechanism, or accepting the limits in the hook header), and the chosen ones are done or the record is deleted.
- Refs: `scripts/claude-hooks/require-local-review.sh` (header "Limits"); CI reviewer findings on PR #233.

### reviewer-misses-main-actor-task-blocking
- Type: task
- Area: skills
- Order: 260
- Source: PR for tm-robustness-d7-main-actor-task
- Problem: The local `pr-reviewer` missed the #219 case (`discardSnapshotFile`, a `FileManager.removeItem`, called in the cancel branch of a `Task { }` inside `TrackingMapView.updateUIView`, a main-actor context) in two scratch runs on the commit before the fix (`428444c`, base `c19d5e1`), with `tm-robustness` D7 in the tree both times. Run 1 (first D7 wording) cited D7/C1 but only as `[important]` for `snapshotDirectory()` ("cheap and not a real blocker") and said nothing about `discardSnapshotFile`; run 2 (D7 tightened once to say every statement of the `Task` body counts) had no finding on the `Task` body and did not cite D7. The CI reviewer found the case on the real PR, through C1 and D6. Two runs are a small sample, and the reviewer's output varies between runs. A text check cannot replace it: in #219 the `FileManager` call was inside `discardSnapshotFile`, called from a nested `if` of the `Task` body. `tm-pr-review` is a protected path, so a checklist change is not made here.
- Done when: audit 61 has compared the local and the CI reviewer on this diff and decided whether a concurrency-specific checklist item or a fixed `TASK` input (the local run got the PR title and description as of the commit, the CI run gets the final description) closes the gap, and the chosen change is done or the record is deleted.
- Refs: `.claude/skills/tm-robustness/SKILL.md` (D7); `.claude/skills/tm-pr-review/SKILL.md` (item 15); PR #219.

### local-reviewer-reads-working-tree-rules
- Type: task
- Area: skills
- Order: 280
- Source: PR for review-task-rehearsal (task 61a, decision 5)
- Problem: The local `pr-reviewer` reads the PR's own `.claude/` and `CLAUDE.md` files from the working tree, while CI's reviewer reads the base's copies (the "Build review inputs" step replaces them), so a PR that edits a skill is judged by the edited skill locally and by the old one in CI. It showed on #234: rule D7 was visible only locally. The `TASK` header that `scripts/review-task.sh` prints repeats CI's sentence that the working tree holds the base's copies, which is not true for a local run. This is an owner decision, not a same-subject fix.
- Done when: the owner decides whether the local input builder copies the base's instruction files into a scratch tree like CI does, and the skills and `scripts/review-task.sh` say what the decision is.
- Refs: `.github/workflows/pr-review.yml` ("Build review inputs"); `scripts/review-task.sh`; `.claude/skills/tm-pr-review/SKILL.md` ("Orchestrator's part"); PR #234.

### ios-history-details-snapshot-delete-on-main-actor
- Type: task
- Area: iosApp/History
- Order: 290
- Source: sweep tm-robustness
- Problem: `tm-robustness` D7 (blocking when it blocks the main actor) and C1 (blocking). `HistoryViewModel.onDeleteActivity` and `DetailsViewModel.onDeleteConfirmed` are `@MainActor` and call `deleteSnapshotFile(forStoredPath:)` (`FileManager.default.removeItem`) inside a plain `Task { }`. That task inherits the main actor, so the file delete runs on the main thread. Count 2 (one cause, the shared helper in `SnapshotFile.swift`). The Android twin is `history-details-snapshot-delete-on-main`, which names only the Kotlin ViewModels. Recorded, not fixed: this sweep changes no code, and the fix (`Task.detached` or an injected deleter) should be chosen together with that record's design.
- Done when: in `iosApp/Packages/History/Sources/History/`, `grep -n 'deleteSnapshotFile' HistoryViewModel.swift DetailsViewModel.swift` shows each call inside `Task.detached` or behind an injected deleter that is not on the main actor; a package test covers the delete after a successful repository delete.
- Refs: `iosApp/Packages/History/Sources/History/HistoryViewModel.swift` (`onDeleteActivity`), `.../DetailsViewModel.swift` (`onDeleteConfirmed`), `.../SnapshotFile.swift` (`deleteSnapshotFile`); `iosApp/Packages/History/Tests/HistoryTests/`; `tm-robustness` C1, D7; `history-details-snapshot-delete-on-main`.

### tracking-session-store-failures-not-surfaced
- Type: task
- Area: domain, data
- Order: 300
- Source: sweep tm-robustness
- Problem: `tm-robustness` E4 (blocking). A failed write or restore of the in-progress tracking session is only logged. `TrackingSessionManager.persist` catches the store's exception and calls `logger.debug` ("Saving the session failed"), and tracking goes on; if every write fails, process death loses the recorded path and the user was never told. `handleRestart` (`RestartAction.kt`) turns a `restore()` that throws after a `START_STICKY` restart into `StopSilently`: the service stops, recording ends, no notice. Count 2. Both code comments state the choice ("No user action can fix a failed write"; "A restore that throws is logged and ends like an empty one"), so whether to surface these failures (an event like `locationIssues`, a notice) is the owner's decision; recorded, not fixed.
- Done when: the owner decides. If surfaced: a failing `TrackingSessionStore.save` reaches the UI as an event or state, and a throwing restore in `handleRestart` leaves a notice, each asserted in `TrackingSessionManagerTest` and `RestartActionTest`. If not: `tm-robustness` E4 names these two paths as accepted exceptions.
- Refs: `domain/src/commonMain/.../tracking/TrackingSessionManager.kt` (`persist`); `data/src/androidMain/.../tracking/RestartAction.kt` (`handleRestart`); `domain/src/commonTest/.../tracking/TrackingSessionManagerTest.kt`; `data/src/androidHostTest/.../tracking/RestartActionTest.kt`; `tm-robustness` E4.

### tracking-control-rules-to-domain
- Type: task
- Area: domain, androidApp/feature-tracking, iosApp/Tracking
- Order: 320
- Source: sweep tm-kmp-shared
- Problem: `tm-kmp-shared` "Where logic lives" puts the can-start/can-pause rules in `domain` ("Do not re-implement it separately in an Android ViewModel and a Swift ViewModel"); the skill gives the rule no severity, read here as `important`. The four rules (`canStart`, `canPause`, `canResume`, `canStop`) are hand-written twice: in Android `TrackingScreenState` and in iOS `TrackingViewModel`. The two copies already disagree. On Android `canStart` is `Idle` and not restoring; on iOS it is `idle` or `finished`, so iOS offers Start over a finished, unsaved session and Android does not. Count 1 cause, 4 rules on each platform. Not the `tracking-metrics-calories-to-domain` record, which names only the metrics extraction and the calorie recompute. Recorded, not fixed: which `canStart` is right is a product decision, and the move changes `domain`, both ViewModels and their tests.
- Done when: `domain` has the four rules as a pure function or property of `TrackingState` with `kotlin.test` cases, and `grep -n -E 'var canStart|val canStart' androidApp/feature-tracking/src/main iosApp/Packages/Tracking/Sources -r` shows each platform only delegating to it; the `Finished` case of `canStart` is the owner's decision, the same on both platforms.
- Refs: `androidApp/feature-tracking/.../TrackingViewModel.kt` (`TrackingScreenState`); `iosApp/Packages/Tracking/Sources/Tracking/TrackingViewModel.swift` (`canStart`, `canPause`, `canResume`, `canStop`); `domain/.../model/TrackingState.kt`; `tm-kmp-shared` ("Where logic lives"); `tracking-metrics-calories-to-domain`.

### live-activity-throttle-uses-wall-clock
- Type: task
- Area: iosApp/Tracking
- Order: 330
- Source: sweep tm-kmp-shared
- Problem: `tm-kmp-shared` "Time": durations are measured with the monotonic clock, and two wall-clock reads are never subtracted (the skill gives no severity, read here as `important`). `TrackingLiveActivityController.update` throttles with `Date()` and `now.timeIntervalSince(lastUpdateDate)`. If the system time moves back (a manual change, a network time correction), the difference stays below `minimumUpdateInterval` and the Live Activity drops every update until the wall clock catches up. Count 1. Recorded, not fixed: this sweep changes no code, and the fix (the shared `Clock.elapsedRealtimeMillis()`, or `ContinuousClock` in Swift) is a choice for the iOS change.
- Done when: `grep -n 'Date()' iosApp/Packages/Tracking/Sources/Tracking/TrackingLiveActivityController.swift` shows no read used for the throttle, and a package test drives the throttle through an injected clock, including a clock that goes back.
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/TrackingLiveActivityController.swift` (`update`, `minimumUpdateInterval`); `tm-kmp-shared` ("Time"); `ios-live-activity-ticker`.

### android-mainactivity-field-injection
- Type: task
- Area: androidApp/app
- Order: 360
- Source: sweep tm-android
- Problem: `tm-android` "Koin" forbids field injection and `KoinComponent` in application code (no severity given; read as `important`). `MainActivity` field-injects three dependencies with `by inject()`: `trackingSessionManager`, `applicationScope` (`inject(APPLICATION_SCOPE)`) and `logger`. Count 3, one file. The skill's own exception names only `TrackingSessionManager`, so two of the three are not even listed (see `android-skill-koin-and-count-text-stale`). Known deviation of `tm-android` with no board record until now. Recorded, not fixed: an Activity is not constructed by Koin, so the replacement (a ViewModel that holds the Stop handling, or `koinInject()`/`get()` at the composition root) is a design choice and changes `MainActivity` and its tests.
- Done when: `grep -n 'by inject' androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/MainActivity.kt` returns nothing, the Stop-intent handling still discards the session in the application scope, and `tm-android`'s Koin exception line is removed.
- Refs: `androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/MainActivity.kt` (`trackingSessionManager`, `applicationScope`, `logger`, `handleStopTrackingIntent`); `androidApp/app/src/test/`; `tm-android` ("Koin", "Known deviations").

### android-viewmodels-koin-lambda-form
- Type: task
- Area: androidApp/feature-route, androidApp/feature-history
- Order: 370
- Source: sweep tm-android
- Problem: `tm-android` "Koin" prefers `viewModelOf(::X)` and allows the lambda form only for a factory method, a qualifier, runtime parameters or post-construction setup (no severity given; read as `important`). `routeModule` registers `RouteViewModel` and `historyUiModule` registers `HistoryViewModel` with `viewModel { X(a = get(), b = get()) }`: only plain constructor arguments, none of the four reasons. Count 2. `DetailsViewModel` and `TrackingViewModel` take runtime parameters and keep the lambda form correctly. Recorded, not fixed: a change to Koin files, small but of another subject than this sweep.
- Done when: `grep -n 'viewModel {' androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/di/RouteModule.kt` returns nothing and `HistoryUiModule.kt` uses `viewModelOf(::HistoryViewModel)` for `HistoryViewModel`; the module's Koin graph tests still pass.
- Refs: `androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/di/RouteModule.kt`; `androidApp/feature-history/src/main/kotlin/dev/roozbahani/trailmetrics/feature/history/di/HistoryUiModule.kt`; `androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/di/AppModule.kt` (the `viewModelOf` pattern); `tm-android` ("Koin").

### android-screen-overload-delegates-to-root
- Type: task
- Area: androidApp/feature-route, androidApp/feature-tracking, androidApp/feature-history, androidApp/app
- Order: 380
- Source: sweep tm-android
- Problem: `tm-android` "Presentation layer" names `<Screen>Screen` the stateless composable (`state` + `onAction`, no ViewModel reference) and `<Screen>Root` the one holding the ViewModel. Each of the four screen files also has a public `<X>Screen(...)` overload that only calls `<X>Root`, so every screen name is declared twice with different meanings (`RouteScreen`, `TrackingScreen`, `HistoryScreen`, `DetailsScreen`). Count 4. It is a known deviation of `tm-android` ("kept so MainActivity's NavHost call sites didn't change") with no board record until now. Recorded, not fixed: the fix changes the four NavHost call sites in `MainActivity` and the UI tests that call the overloads.
- Done when: `grep -rn 'NavHost entry point' androidApp/feature-route/src/main androidApp/feature-tracking/src/main androidApp/feature-history/src/main` returns nothing, `MainActivity`'s NavHost calls the Root composables, each `<X>Screen` name is declared once, and the "Known deviations" bullet of `tm-android` is removed.
- Refs: `androidApp/feature-route/.../RouteScreen.kt`, `androidApp/feature-tracking/.../TrackingScreen.kt`, `androidApp/feature-history/.../HistoryScreen.kt` and `.../DetailsScreen.kt` (the doc comment "NavHost entry point"); `androidApp/app/.../MainActivity.kt` (`TrailMetricsNavHost`); `tm-android` ("Presentation layer", "Known deviations").

### route-waypoint-marker-ad-hoc-color
- Type: task
- Area: androidApp/feature-route
- Order: 390
- Source: sweep tm-android
- Problem: `tm-android` "Compose": colors come from `core-ui`'s `designsystem/theme`, with no ad-hoc color literals in features (no severity given; read as `important`). The waypoint marker icon in `RouteScreen` is tinted with `Color.Red`, not a theme color (`TrailRed` or `MaterialTheme.colorScheme.error`). Count 1. The other `Color.*` uses are in the theme files themselves and in `core-ui`'s `CurrentLocationMarker` (white border), which is not a feature and was read as not a violation. Recorded, not fixed: this sweep changes no code, and which theme color the marker should use is a design choice.
- Done when: `grep -n 'Color\.Red' androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt` returns nothing and the marker tint is a theme color.
- Refs: `androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt` (the `MarkerComposable` of the waypoints); `androidApp/core-ui/src/main/kotlin/dev/roozbahani/trailmetrics/core/designsystem/theme/Color.kt`; `tm-android` ("Compose").

### route-waypoint-marker-no-content-description
- Type: task
- Area: androidApp/feature-route
- Order: 400
- Source: sweep tm-android
- Problem: `tm-android` "Compose": meaningful `contentDescription` (string resource, `cd_*` key) on interactive or informational elements, `null` only for decorative ones (no severity given; read as `important`). The waypoint marker in `RouteScreen` is a `MarkerComposable` whose `onClick` removes the waypoint, and its `Icon` has `contentDescription = null`. Count 1. The other `null` descriptions were read: they are icons next to a text label, a decorative snapshot image and the bottom bar items, and are decorative. Whether a map marker is reachable by a screen reader at all depends on the Maps Compose version, so the fix needs a decision. Recorded, not fixed.
- Done when: the waypoint marker's `Icon` has a `contentDescription` from a `cd_*` string resource (or the owner records that map markers are exempt in `tm-android`), and `grep -n 'cd_' androidApp/core-ui/src/main/res/values/strings.xml` lists it.
- Refs: `androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt` (`MarkerComposable`); `androidApp/core-ui/src/main/res/values/strings.xml`; `tm-android` ("Compose").

### composables-transform-data-in-composition
- Type: task
- Area: androidApp/feature-route, androidApp/feature-history
- Order: 410
- Source: sweep tm-android
- Problem: `tm-android` "Compose": composables render `state`, with zero business logic and zero data transformation (no severity given; read as `important`). Two composables transform data in composition: `RouteScreen` maps `route.points` to coordinates (`route.points.map { it.coordinates }`) for `RoutePolyline` on every recomposition, and `ActivityRow` in `HistoryScreen` builds a `DateFormat` with `DateFormat.getDateTimeInstance(...)` and formats the start time for every row on every recomposition. Count 2. The second also breaks `tm-robustness` P2 (no allocation in composition; `remember` a derived value), which the stage 1 sweep (#238) did not find. Recorded, not fixed: the fix moves the mapping into the state (`RouteState`) and the date into a display value or a `remember`ed formatter, which changes state classes and tests.
- Done when: `grep -n 'points.map' androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt` returns nothing, `grep -n 'getDateTimeInstance' androidApp/feature-history/src/main/kotlin/dev/roozbahani/trailmetrics/feature/history/HistoryScreen.kt` returns nothing or the formatter is created once per screen, and the existing UI tests pass.
- Refs: `androidApp/feature-route/.../RouteScreen.kt` (`RoutePolyline(points = ...)`); `androidApp/feature-history/.../HistoryScreen.kt` (`ActivityRow`); `tm-android` ("Compose"); `tm-robustness` P2.

### opt-in-without-reason-or-too-wide
- Type: task
- Area: androidApp/feature-route, data
- Order: 420
- Source: sweep tm-android
- Problem: `tm-android` "No deprecated APIs (Kotlin)": opt in as narrowly as possible, at the call expression or the smallest enclosing declaration, with a comment saying why (no severity given; read as `important`; `tm-kmp-shared` applies the Kotlin rules to `data`). Three of five `@OptIn` annotations have no comment: `UserProfileBottomSheet` in `RouteScreen` (`ExperimentalMaterial3Api`), `getDatabaseBuilder` in `DatabaseBuilder.ios.kt` and `IosLocationRepositoryImpl` (both `ExperimentalForeignApi`). The last is on the whole class, wider than the members that use the cinterop API. Count 3 (one of them also too wide). The `MapEffect` opt-in in `TrackingScreen` and the one in `SystemClock.ios.kt` give their reason and are narrow. Recorded, not fixed: this sweep changes no code.
- Done when: every `@OptIn` in production Kotlin has a comment line saying why, and `IosLocationRepositoryImpl` opts in on the members that need it; `grep -rn -B1 '@OptIn' androidApp data --include=*.kt` shows a comment above each.
- Refs: `androidApp/feature-route/src/main/kotlin/dev/roozbahani/trailmetrics/feature/route/RouteScreen.kt` (`UserProfileBottomSheet`); `data/src/iosMain/kotlin/dev/roozbahani/trailmetrics/data/local/database/DatabaseBuilder.ios.kt`; `data/src/iosMain/kotlin/dev/roozbahani/trailmetrics/data/location/IosLocationRepositoryImpl.kt`; `tm-android` ("No deprecated APIs (Kotlin)").

### unused-template-colors-in-core-ui
- Type: task
- Area: androidApp/core-ui
- Order: 430
- Source: sweep tm-android
- Problem: `tm-android` "No dead code": unused `internal`/`public` code is not caught by detekt, so check it yourself (no severity given; read as `important`). `core-ui`'s `Color.kt` keeps six default-template colors (`Purple80`, `PurpleGrey80`, `Pink80`, `Purple40`, `PurpleGrey40`, `Pink40`) under "Default template colors". `git grep` finds each name only in its own declaration, so none is used by any module, test or resource. Count 6, one file. Recorded, not fixed: this sweep changes no code (and `UnusedPrivateProperty` would not flag a public `val`).
- Done when: `git grep -n -E 'Purple80|PurpleGrey80|Pink80|Purple40|PurpleGrey40|Pink40' -- . ':!BOARD.md'` returns nothing and the "Default template colors" comment is gone.
- Refs: `androidApp/core-ui/src/main/kotlin/dev/roozbahani/trailmetrics/core/designsystem/theme/Color.kt`; `tm-android` ("No dead code").

### ios-viewmodels-delete-snapshot-files
- Type: task
- Area: iosApp/History
- Order: 450
- Source: sweep tm-ios
- Problem: `tm-ios` "Architecture" (Violation: `blocking` for data access): a ViewModel holds presentation state only, with no file, database or HTTP access of its own. `HistoryViewModel.onDeleteActivity` and `DetailsViewModel.onDeleteConfirmed` call `deleteSnapshotFile(forStoredPath:)`, a free function in `SnapshotFile.swift` that resolves the path against Application Support and calls `FileManager.default.removeItem`. Count 2, one cause. This is the architecture side of `ios-history-details-snapshot-delete-on-main-actor` (rule `tm-robustness` D7/C1, the thread it runs on): a `Task.detached` there would fix the thread and leave the ViewModels touching files. Android's twin is `tracking-viewmodel-snapshot-file-access`. Recorded, not fixed: the fix adds an injected deleter (a protocol with a default-parameter `init`, and a fake for the package tests), a design that belongs with the two records above.
- Done when: `grep -n 'deleteSnapshotFile\|FileManager' iosApp/Packages/History/Sources/History/HistoryViewModel.swift iosApp/Packages/History/Sources/History/DetailsViewModel.swift` returns nothing, the deletion sits behind an injected type the package tests fake, and it runs off the main actor (so `ios-history-details-snapshot-delete-on-main-actor` is also done).
- Refs: `iosApp/Packages/History/Sources/History/HistoryViewModel.swift`, `.../DetailsViewModel.swift`, `.../SnapshotFile.swift`; `iosApp/Packages/History/Tests/HistoryTests/`; `tm-ios` ("Architecture"); `ios-history-details-snapshot-delete-on-main-actor`; `tracking-viewmodel-snapshot-file-access`.

### ios-tracking-viewmodel-switch-default-on-kotlin-enum
- Type: task
- Area: iosApp/Tracking
- Order: 460
- Source: sweep tm-ios
- Problem: `tm-ios` "SKIE interop": keep the `switch onEnum(of: value)` exhaustive so a new Kotlin case breaks the Swift build (no severity given; read as `important`). In `TrackingViewModel`, `canStop` and `currentPath` switch on `onEnum(of: trackingState)` and end in `default:`, so a new `TrackingState` case would compile and silently fall into the default (not stoppable, empty path). Count 2, one file (`currentMetrics` lists every case since PR restore-fixes). The other switches on `onEnum(of:)` (`ContentView`, `HistoryViewModel`, `RouteUiError+Message`, `onStopClicked`) list every case. Recorded, not fixed: this sweep changes no code; it overlaps with `tracking-control-rules-to-domain`, which may move these rules to `domain`.
- Done when: `grep -n 'default:' iosApp/Packages/Tracking/Sources/Tracking/TrackingViewModel.swift` returns nothing and each of the two properties lists all `TrackingState` cases (or is replaced by the shared domain rule).
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/TrackingViewModel.swift` (`canStop`, `currentPath`); `tm-ios` ("SKIE interop from Swift"); `tracking-control-rules-to-domain`.

### ios-contentview-calls-koinhelper
- Type: task
- Area: iosApp
- Order: 470
- Source: sweep tm-ios
- Problem: `tm-ios` "Koin / KoinHelper" and "ViewModel shape": never call `KoinHelper()` anywhere except in a default argument or the composition root (no severity given; read as `important`). `ContentView.handleOpenURL` calls `KoinHelper().trackingSessionManager().currentState.value` and switches on it to decide whether to select the Route tab. `ContentView` is a View, not the composition root (`TrailMetricsApp.init`), so the read bypasses injection and no test can fake it. Count 1. Recorded, not fixed: the fix (the app-level state or a small ViewModel for the tab selection, injected with a default parameter) is a design choice for the app target.
- Done when: `grep -n 'KoinHelper()' iosApp/TrailMetrics/ContentView.swift` returns nothing and the open-URL handling reads the session state through an injected dependency, with a test or a UI-test scenario for the tab switch.
- Refs: `iosApp/TrailMetrics/ContentView.swift` (`handleOpenURL`); `iosApp/TrailMetrics/TrailMetricsApp.swift`; `tm-ios` ("Koin / KoinHelper").

### ios-viewmodel-state-not-private-set
- Type: task
- Area: iosApp/Route, iosApp/History
- Order: 480
- Source: sweep tm-ios
- Problem: `tm-ios` "ViewModel shape": use `public private(set)` for state the View must not write (no severity given; read as `important`). Ten `@Published public var` properties are never written by a View (`grep` finds no `viewModel.<name> =` and no `$viewModel` binding anywhere): `RouteViewModel` `startPoint`, `waypoints`, `generatedRoute`, `userProfile`, `selectedActivityType`, `isLoading`; `HistoryViewModel` `activities`, `isLoading`; `DetailsViewModel` `activity`, `isLoading`. Count 10 in 3 files. `TrackingViewModel` and the two `errorMessage` properties already use `private(set)`. The skill's own ViewModel example also shows `@Published public var activities` and `isLoading`, so the example must change with the code. Recorded, not fixed: this sweep changes no code; package tests that assign the properties would need the setter back or a different seam.
- Done when: `grep -rn '@Published public var' iosApp/Packages/*/Sources` returns nothing, the package tests pass, and the example in `tm-ios` ("ViewModel shape") shows `public private(set)`.
- Refs: `iosApp/Packages/Route/Sources/Route/RouteViewModel.swift`; `iosApp/Packages/History/Sources/History/HistoryViewModel.swift`, `.../DetailsViewModel.swift`; `tm-ios` ("ViewModel shape").

### ios-design-system-unused-colors
- Type: task
- Area: iosApp/DesignSystem
- Order: 490
- Source: sweep tm-ios
- Problem: `tm-ios` "No dead code": no unused declarations (`tm-android`, "No dead code", which it refers to, notes that unused public code is not caught by a linter). `Color+TrailMetrics.swift` in `DesignSystem` declares `trailGreenLight`, `trailBlue` and `trailBlueLight`; `git grep` finds each name only in its own declaration, so no package, target or test uses them (`trailGreen`, `trailRed` and `trailAmber` are used). Count 3, one file. They mirror Android's brand colors and may be wanted for the Figma design system epic, so whether to delete or keep them is a decision. Recorded, not fixed.
- Done when: `git grep -n -E 'trailGreenLight|trailBlueLight|trailBlue\b' -- iosApp` returns nothing, or each is used by a view, or the owner records that the tokens are kept for the design system.
- Refs: `iosApp/Packages/DesignSystem/Sources/DesignSystem/Color+TrailMetrics.swift`; `tm-ios` ("No dead code"); `figma-design-system`.

### swiftlint-unused-import-never-runs
- Type: task
- Area: iosApp, scripts
- Order: 500
- Source: sweep tm-ios
- Problem: `tm-ios` "No dead code" says "No unused imports (`unused_import` is enabled)". `iosApp/.swiftlint.yml` lists `unused_import` under `opt_in_rules`, but it is an analyzer rule that only `swiftlint analyze` runs: `swiftlint lint --strict` exits 0 while printing "'unused_import' should be listed in the 'analyzer_rules' configuration section ... only run by 'swiftlint analyze'", and no script or workflow runs `swiftlint analyze` (the gate and CI run `lint`). So the rule is inert and unused imports are not checked by any tool. Count 1 rule. A mechanical rule that no tool runs is not a pass. Recorded, not fixed: SwiftLint config and CI are protected, and `analyze` needs a compiler log from an `xcodebuild` run, so adding it is a decision about the gate's cost.
- Done when: `swiftlint analyze` runs on the iOS sources in the gate and CI with `unused_import` under `analyzer_rules` and passes, or the line is removed from `opt_in_rules` and `tm-ios` no longer claims the rule is enabled.
- Refs: `iosApp/.swiftlint.yml`; `scripts/pre-push-check.sh`; `.github/workflows/ci.yml` (`ios-main`); `tm-ios` ("No dead code", "SwiftLint").

### swift-test-wait-until-fixed-two-second-bound
- Type: task
- Area: iosApp/Packages/TestSupport, iosApp package tests
- Order: 520
- Source: sweep tm-testing
- Problem: `tm-testing` fixes the wait rules of the XCUITests (D5: `waitForExistence(timeout: 10)`, no fixed delay; D6: a red run is logged, not retried) and states no bound for the Swift package tests' own wait helper. That helper, `waitUntil` in `TestSupport` (and `waitUntilOnlyReference`, which calls it), gives every wait a default `timeout` of two seconds; only the first wait of a test process gets 120 seconds (`coldStartTimeout`). No call site passes another timeout. Count: 123 `await waitUntil { ... }` and 14 `waitUntilOnlyReference(&...)` calls in 14 test files of the History, Route and Tracking packages. It has failed twice on CI with "Condition not met within 2.0 seconds" on a loaded runner: `TrackingViewModelFinishTests.test_onFinishClicked_afterFailedSave_savesAgain` (flake-log entry `ios-tracking-finish-failed-save-wait`, board record `ios-tracking-finish-test-fixed-wait`) and `RouteViewModelPendingEventsTests.test_eventAfterConsumerCancelled_isDeliveredOnceToNextStreamOnly` (flake-log entry `ios-route-pending-events-wait`, run 42813382887, a red push run of `main` on unchanged Swift sources). The older board record names only the Tracking Finish tests. Recorded, not fixed: the bound lives in `TestSupport`, which three packages share, and the right value or mechanism (a longer or scaled default, or waiting without a bound) is a decision; this sweep changes no code.
- Done when: `grep -n 'seconds(2)' iosApp/Packages/TestSupport/Sources/TestSupport/Support/WaitUntil.swift` returns nothing (or the default is a value the owner chose, with a comment saying why), the package tests pass, the two flake-log entries are set to `fixed` with this fix, and `ios-tracking-finish-test-fixed-wait` is deleted in the same PR.
- Refs: `iosApp/Packages/TestSupport/Sources/TestSupport/Support/WaitUntil.swift` (`waitUntil`, `waitUntilOnlyReference`, `coldStartTimeout`); `iosApp/Packages/Route/Tests/RouteTests/RouteViewModelPendingEventsTests.swift`; `iosApp/Packages/Tracking/Tests/TrackingTests/TrackingViewModelFinishTests.swift`; `CI_FLAKES.md`; `ios-tracking-finish-test-fixed-wait`; `wait-until-cancellation-spin`; `tm-testing` ("XCUITest", D5, D6).

### pause-resume-joins-path-with-a-straight-segment
- Type: task
- Area: domain, androidApp, iosApp
- Order: 540
- Source: PR persist-tracking-restore-ios
- Problem: The owner saw, on an Android device, that after Pause and Resume the recorded line joins the last point before the Pause to the first point after the Resume with a straight segment (a chord across a circle). What the code does, read in the files: `UpdateTrackingStateUseCase` handles `Pause` and `Resume` without touching the path, and the first `LocationReceived` after the Resume adds `path.last().distanceTo(newCoordinates)` to `distanceMeters`, so the jump is counted as distance, while the time of the pause is not counted (`Resume` sets `lastUpdateElapsedRealtimeMillis`); the path is a plain `List<Coordinates>`, so it has no gap marker and the Pause leaves no trace in it. Android draws the whole path as one `Polyline` (`RoutePolyline` in `TrackingScreen`), and iOS draws it as one `GMSPolyline` (`TrackingMapView`, `recordedPathToDraw`), so both show the chord; the saved activity keeps the same list. A restored session adds one more such jump (it comes back Paused, and its Resume continues from the last stored point). Not changed here: whether a pause splits the line and whether the jump counts as distance is a product decision with a model change in `domain`, both maps and the stored form.
- Done when: the owner decides whether a pause splits the line and whether the jump counts as distance.
- Refs: `domain/.../usecase/UpdateTrackingStateUseCase.kt` (`handleResume`, `handleLocationReceived`); `androidApp/core-ui/.../map/RoutePolyline.kt`; `androidApp/feature-tracking/.../TrackingScreen.kt`; `iosApp/Packages/Tracking/Sources/Tracking/TrackingMapView.swift`; `domain/.../model/TrackingMetrics.kt` (`path`).

### ios-ui-test-restored-session-offer
- Type: task
- Area: iosApp/TrailMetricsUITests, shared-uitest
- Order: 550
- Source: PR route-draft-restore
- Problem: No iOS UI test reaches the saved-session offer of a relaunched app (from the iOS restore review of #248). What the files show: `ContentView` runs `savedSessionOffer.restoreOnce()` in a `.task` and shows the offer from `SavedSessionOfferModel.offer`; in UI-test mode `UiTestTrackingSessionStore.load()` always returns null, so no `UiTestScenario` (`FailedDelete`, `DeleteTwice`, `GenerateTwice`, `GenerateThenReset`, `FinishTwice`) can have a stored session, and `iosApp/TrailMetricsUITests` has no test of the offer; only the Swift unit tests `SavedSessionOfferTests` cover the model, not the view that shows it or what a tap on it does. Recorded, not fixed: a new scenario and its fake store are a UI-test task of their own (`docs/epics/ios-ui-tests.md`), not of the route draft.
- Done when: a `UiTestScenario` launches the app with a stored Paused session, and a UI test sees the offer and, through it, the restored session on the tracking screen (D5 determinism rules of `tm-testing` "XCUITest").
- Refs: `iosApp/TrailMetrics/ContentView.swift` (`restoreOnce`); `iosApp/Packages/Tracking/Sources/Tracking/SavedSessionOffer.swift`; `shared-uitest/src/iosMain/.../UiTestFakes.kt` (`UiTestTrackingSessionStore`), `UiTestScenario.kt`; `docs/epics/ios-ui-tests.md`.

### ios-tracking-start-not-blocked-while-restoring
- Type: task
- Area: iosApp/Tracking
- Order: 560
- Source: PR route-draft-restore
- Problem: On iOS a tap on Start before `TrackingSessionManager.restore()` returns is not blocked (from the iOS restore review of #248). What the files show: Android's `TrackingViewModel` keeps `isRestoring` true until its own `restore()` call returns, and `start()` returns early while it is true (`TrackingScreenState.canStart` is `trackingState is Idle && !isRestoring`); on iOS the restore runs once in `SavedSessionOfferModel.restoreOnce()` (from `ContentView`'s `.task`), and `TrackingViewModel.canStart` is true for `.idle` and `.finished` with no restore check, and `onStartClicked()` calls `trackingSessionManager.start(...)` directly. A session started while the read runs makes `restore()` return the live state without restoring, and that session's first save replaces the stored one. Recorded, not fixed: of another subject (the tracking screen), and where iOS should wait (the offer model or the tracking ViewModel) is a design choice. The Live Activity of a killed process is task 59f, not this record.
- Done when: on iOS, Start does nothing (or is not offered) until the stored session has been read, as on Android, with a Swift test that holds the store's load.
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/TrackingViewModel.swift` (`canStart`, `onStartClicked`); `iosApp/Packages/Tracking/Sources/Tracking/SavedSessionOffer.swift` (`restoreOnce`); `androidApp/feature-tracking/.../TrackingViewModel.kt` (`isRestoring`, `start`).

## Drift

### data-kover-comment-stale-figure
- Type: drift
- Area: data
- Order: 230
- Source: PR for location-current-swallows-cancellation
- Problem: The comment above the Kover floor in `data/build.gradle.kts` gives the measured coverage as 44.38% (142/320 lines). With `AndroidLocationRepositoryImplTest` the `data` host report measures 49.38% (160 of 324 lines) and the floor in `config/kover-floors.properties` is 48. `data/build.gradle.kts` is a protected path, so the comment was left as it is.
- Done when: the comment states the current measured figure, or no longer quotes one, in a PR that may touch the protected path.
- Refs: `data/build.gradle.kts` (Kover floor comment); `config/kover-floors.properties`.

### ownerless-folders-markdown-only-comments
- Type: drift
- Area: .claude
- Order: 232
- Source: PR for pr-review-item-3-reference-skill-files
- Problem: `scripts/check-protected-paths.py` now protects a file in the five ownerless skill folders whose name does not end in `.md`, but two lines still say every file there is open: the comment above the five ownerless lines in `.github/CODEOWNERS` ("an agent may edit them and add files to them") and the "Boundaries" paragraph in `.claude/skills/tm-pr-workflow/SKILL.md` ("every file in them is open"). Both are protected paths outside this PR's authorization.
- Done when: both say that Markdown files in those folders are open and any other file is protected, in a PR that may touch the protected paths.
- Refs: `.github/CODEOWNERS` (reference skills comment); `.claude/skills/tm-pr-workflow/SKILL.md` ("Boundaries"); `scripts/check-protected-paths.py` (`protecting_pattern`).

### skill-lists-omit-new-skills
- Type: drift
- Area: docs
- Order: 243
- Source: PR for tm-robustness-skill
- Problem: Two lists of the skills do not name them all. `README.md` ("`.claude/skills/`") and `docs/architecture/OVERVIEW.md` ("`.claude/skills/`") list `tm-kmp-shared`, `tm-android`, `tm-ios`, `tm-testing`, `tm-pr-workflow` and `epic-orchestration`, and omit `tm-agent-loop`, `tm-pr-review` and `tm-robustness`. `docs/architecture/` is protected and outside this PR's authorization, and the omission of the first two predates it.
- Done when: both lists name every skill folder under `.claude/skills/`, in a PR that may touch `docs/architecture/`.
- Refs: `README.md` (documentation list); `docs/architecture/OVERVIEW.md` (`.claude/skills/` line).

### snapshot-saver-doc-claims-wrong-isolation
- Type: drift
- Area: ios
- Order: 270
- Source: PR for tm-robustness-d7-main-actor-task
- Problem: The doc comment of `writeMapSnapshot` in `iosApp/Packages/Tracking/Sources/Tracking/MapSnapshotSaver.swift` says the app target builds with `NonisolatedNonsendingByDefault`, so the function runs on its caller's actor. The function is defined in the `Tracking` package, whose `Package.swift` (swift-tools-version 5.9, no `swiftSettings`) does not set it; only the app target sets `SWIFT_APPROACHABLE_CONCURRENCY = YES` (`project.pbxproj`). So the original statement (a nonisolated `async` function runs on the global executor) may have been right for that module. Read from the files, not compiled. Changing the comment is a Swift change and would start the iOS jobs, so it is not done in the PR that found it.
- Done when: the comment says what is true for that module (the call site's `Task.detached` stays), in a PR that may touch iOS code.
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/MapSnapshotSaver.swift` (`writeMapSnapshot`); `iosApp/Packages/Tracking/Package.swift`; `iosApp/TrailMetrics.xcodeproj/project.pbxproj`; `tm-robustness` D7.

### detekt-exception-name-exemption-undocumented
- Type: drift
- Area: .claude/skills/tm-robustness, config
- Order: 310
- Source: sweep tm-robustness
- Problem: `tm-robustness` E2's Enforced line says detekt `SwallowedException` does not check "an exception named `_`", and E1's names `TooGenericExceptionCaught` with no exemption. detekt 1.23.8's default for both rules is `allowedExceptionNameRegex: '_|(ignore|expected).*'`, and `config/detekt/detekt.yml` (`buildUponDefaultConfig = true`) does not override it. So a catch whose variable starts with `expected` or `ignore` is checked by neither rule. Five production `catch (expected: Exception)` blocks rely on it: `TrackingSessionManager` (`clearSession`, `persist`), `RestartAction.kt` (`handleRestart`), `MainActivity` (`handleStopTrackingIntent`), `SavedSessionOfferViewModel` (`init`). Each was read: each handles its failure on purpose, so none is an E1 or E2 violation (the E4 side is `tracking-session-store-failures-not-surfaced`). Only the rule text is wrong. Not fixed: this sweep changes no skill or config, and narrowing the regex (lint config, protected) or documenting it is a decision.
- Done when: E1's and E2's Enforced lines name the `expected`/`ignore` name exemption, or `config/detekt/detekt.yml` sets `allowedExceptionNameRegex: '_'` for both rules and the five catches are renamed or suppressed with approval.
- Refs: `.claude/skills/tm-robustness/SKILL.md` (E1, E2); `config/detekt/detekt.yml`; `build.gradle.kts` (`buildUponDefaultConfig`); the five files above.

### route-error-module-stated-as-core
- Type: drift
- Area: CLAUDE.md, .claude/skills/tm-kmp-shared
- Order: 340
- Source: sweep tm-kmp-shared
- Problem: `CLAUDE.md` ("Map": "`core` commonMain only: `AppRoute`, `RouteError`/`RouteUiError`") and `tm-kmp-shared` ("Module boundaries": "`core` (commonMain only): `AppRoute`, `RouteError`/`RouteUiError`") say `RouteError` is in `core`. It is in `domain` (`domain/src/commonMain/.../domain/model/RouteError.kt`); `core` holds only `AppRoute.kt` and `RouteUiError.kt`. The same skill's "Existing error model" and `core/README.md` call it domain-level, so the texts also disagree with each other. Not fixed: this sweep changes no skill and no `CLAUDE.md`.
- Done when: both lines name only `AppRoute` and `RouteUiError` for `core` (and `RouteError` under `domain`), matching `find core/src -name '*.kt'`.
- Refs: `CLAUDE.md` ("Map"); `.claude/skills/tm-kmp-shared/SKILL.md` ("Module boundaries"); `core/README.md`; `domain/.../model/RouteError.kt`.

### android-viewmodel-count-stale
- Type: drift
- Area: CLAUDE.md, .claude/skills
- Order: 350
- Source: sweep tm-kmp-shared
- Problem: Four texts count the Android ViewModels as four: `CLAUDE.md` ("Presentation layer: MVI": "All four Android ViewModels"), `tm-android` (MVI "Current code: all four ViewModels follow this shape"), `tm-robustness` M2 ("the four ViewModels hold none") and `tm-pr-workflow` Boundaries ("All four Android ViewModels are on MVI since #54"). There are five: `SavedSessionOfferViewModel` (`androidApp/app`) was added later, with `state`, `onAction` and `events`. The claims still hold for it as read here (MVI shape, no `Context`), only the count and the lists of names are stale. Not fixed: this sweep changes no skill and no `CLAUDE.md`.
- Done when: the four texts name all five ViewModels or drop the count, matching `grep -rn 'class .*ViewModel' androidApp/*/src/main`.
- Refs: `CLAUDE.md`; `.claude/skills/tm-android/SKILL.md`; `.claude/skills/tm-robustness/SKILL.md`; `.claude/skills/tm-pr-workflow/SKILL.md`; `androidApp/app/.../SavedSessionOfferViewModel.kt`.

### android-skill-koin-and-count-text-stale
- Type: drift
- Area: .claude/skills/tm-android
- Order: 440
- Source: sweep tm-android
- Problem: Two statements in `tm-android` ("Koin") disagree with the code. (1) "Today every module uses the lambda form, including `HistoryViewModel` and `RouteViewModel`": `androidApp/app`'s `appModule` registers `SavedSessionOfferViewModel` with `viewModelOf(::SavedSessionOfferViewModel)`, so the lambda form is not used by every module. (2) "Existing exception: `MainActivity` field-injects `TrackingSessionManager` with `by inject()`": `MainActivity` field-injects three dependencies (`trackingSessionManager`, `applicationScope`, `logger`), so the exception line names one of three. Count 2 lines. The "four ViewModels" count of the same skill is already `android-viewmodel-count-stale`. Not fixed: this sweep changes no skill.
- Done when: the lambda-form sentence names the modules that still use it (`routeModule`, `historyUiModule`, `trackingUiModule`) and the `MainActivity` exception lists the three injected fields, or both lines are removed with the code fixes `android-viewmodels-koin-lambda-form` and `android-mainactivity-field-injection`.
- Refs: `.claude/skills/tm-android/SKILL.md` ("Koin", "Known deviations"); `androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/di/AppModule.kt`; `androidApp/app/src/main/kotlin/dev/roozbahani/trailmetrics/MainActivity.kt`; `android-viewmodel-count-stale`.

### ios-skill-cast-exception-too-narrow
- Type: drift
- Area: .claude/skills/tm-ios
- Order: 510
- Source: sweep tm-ios
- Problem: `tm-ios` "Architecture" says: never an `as?`/`is` cast on an abstraction to reach a concrete type, and "decoding a bridged Kotlin exception, as `RouteViewModel`'s `underlyingRouteError` does, is the one exception". Three more casts in production Swift are not that: `RouteViewModel` tests `error is CancellationError` in a `catch` (Swift concurrency cancellation), `RouteMapView` casts `marker.userData as? RoutePoint` (the Google Maps API stores `Any?`), and `RouteMapConfiguration` casts the Info.plist value `as? String`. Count 3, all forced by an Apple or Google API returning an abstraction. Read as not violations of the rule's intent, so the text is wrong, not the code. Not fixed: this sweep changes no skill.
- Done when: the sentence lists these kinds of cast (a cast required by a system or SDK API that returns `Any`, and Swift's `CancellationError` check) or says "unless the API returns an abstraction", matching `grep -rn -E ' as\? | is [A-Z]' iosApp/Packages/*/Sources`.
- Refs: `.claude/skills/tm-ios/SKILL.md` ("Architecture"); `iosApp/Packages/Route/Sources/Route/RouteViewModel.swift`, `.../RouteMapView.swift`, `.../RouteMapConfiguration.swift`.

### tm-testing-junit5-decision-not-in-docs
- Type: drift
- Area: .claude/skills/tm-testing
- Order: 530
- Source: sweep tm-testing
- Problem: `tm-testing` ("Stack") says "No JUnit5 anywhere in this project (evaluated and rejected, see `docs/architecture`)". `docs/architecture` (`ADR-001`, `ADR-002`, `ADR-003`, `OVERVIEW.md`) has no mention of JUnit, JUnit 5 or Jupiter (`grep -rni junit docs/architecture` returns nothing); the only docs that name JUnit4 are in `docs/epics/mvi-presentation-migration.md`. The rule itself holds in the code (no Jupiter import, no Jupiter entry in the version catalog), so only the pointer is wrong. Count 1 line. Not fixed: this sweep changes no skill, and `docs/architecture` is protected (an ADR that records the decision would be a new document).
- Done when: the sentence drops "evaluated and rejected, see `docs/architecture`" or points at an ADR that records the decision, so that `grep -rni junit docs/architecture` agrees with the skill text.
- Refs: `.claude/skills/tm-testing/SKILL.md` ("Stack"); `docs/architecture/`; `CLAUDE.md` ("Testing stack").
