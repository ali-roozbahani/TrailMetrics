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

### tracking-session-lost-on-process-death
- Type: task
- Area: domain, data, androidApp, iosApp
- Order: 20
- Source: PR for tm-robustness-skill
- Problem: The in-progress session exists only in `TrackingSessionManager`'s in-memory `MutableStateFlow`. After Android process death `TrackingService` (`START_STICKY`) restarts with a null intent, shows the "Setting up..." notification and observes an `Idle` state with no location collection, so a foreground service runs with nothing to track and the recorded path is gone. After iOS termination the session is gone as well (no persistence, no `scenePhase` handling). Persisting a session needs a design decision (what is stored, how often, restore or discard) that only the owner can make.
- Done when: the decision is recorded, an in-progress session is restored or ended visibly after process death on Android and termination on iOS, the restarted service never idles with an empty notification, and tests cover the restore path.
- Refs: `domain/.../tracking/TrackingSessionManager.kt`; `data/src/androidMain/.../tracking/TrackingService.kt`; `data/src/iosMain/.../tracking/IosTrackingServiceLauncher.kt`; `tm-robustness` R2, R5.

### route-draft-lost-on-process-death
- Type: task
- Area: androidApp/feature-route, iosApp/Route
- Order: 30
- Source: PR for tm-robustness-skill
- Problem: The route being planned (start point, waypoints, generated route, chosen activity type) lives only in `RouteViewModel` (`RouteState`) and its Swift twin; there is no `SavedStateHandle`, `rememberSaveable` or `@SceneStorage` anywhere in the app, so process death on either platform drops the plan. Whether the draft is worth persisting is a product decision.
- Done when: the owner decides; if yes, the draft survives process death on both platforms with a test each, if no, `tm-robustness` R1 records the screen as accepted.
- Refs: `androidApp/feature-route/.../RouteViewModel.kt` (`RouteState`); `iosApp/Packages/Route/Sources/Route/RouteViewModel.swift`; `tm-robustness` R1.

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

### prune-merged-branches-gate-and-codeowners
- Type: task
- Area: scripts, .github
- Order: 246
- Source: PR for prune-merged-branches-script-and-hook
- Problem: `scripts/prune-merged-branches.sh` is a new script, but `.github/CODEOWNERS` has no line for it (so it is unprotected, unlike every other workflow script) and `scripts/pre-push-check.sh` does not run its self-test or the new hook's (only CI's `tooling` job does, as the owner decided). Both files are protected and outside the owner's authorization for that PR, so they are a human decision, not part of it.
- Done when: `/scripts/prune-merged-branches.sh` has a CODEOWNERS line (`scripts/check-protected-paths.sh --validate` passes), and the gate runs `scripts/prune-merged-branches.sh --self-test` and `scripts/claude-hooks/block-branch-create-while-merged-branches.sh --self-test` next to the other self-tests, or the owner records why not.
- Refs: `.github/CODEOWNERS`; `scripts/pre-push-check.sh` (the "push hook self-test" step); `.github/workflows/ci.yml` `tooling`.

### prune-merged-branches-checked-out-in-worktree
- Type: task
- Area: scripts
- Order: 247
- After: prune-merged-branches-gate-and-codeowners
- Source: PR for prune-merged-branches-script-and-hook
- Problem: `scripts/prune-merged-branches.sh` exits 4 when a branch whose PR is merged is checked out in another linked worktree (`git branch -D` refuses), so the branch-create hook then blocks with "do not bypass" and only the human's break-glass helps. How such a branch is reported (kept and printed, or removed with its worktree) changes the output contract the owner fixed (`<branch> <MERGED-deleted|OPEN #n|NO_PR>`), so it is a human decision.
- Done when: the owner has decided the case, the script handles a merged branch checked out in another worktree without a dead end for the hook, and its self-test covers it.
- Refs: `scripts/prune-merged-branches.sh`; `scripts/claude-hooks/block-branch-create-while-merged-branches.sh`.

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
