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

### agentic-dev-loop
- Type: epic
- Area: scripts, .github, .claude, iosApp, androidApp
- Order: 40
- Source: chat 2026-10-02
- Problem: Every task needs the human as reviewer, merger and Tier 2 tester, which is the slowest part of development.
- Done when: a human-approved plan under `docs/epics/` comes first. Then: (1) a deterministic test seam (fakes for location, directions and storage injectable at app launch) and UI-test targets exist on Android (Compose UI tests); on iOS (XCUITest) the UI-test target, the launch-time seam, the CI UI suite and the smoke test in the local gate are done; (2) an independent reviewer agent with a fresh context reviews every PR from git against the task's Done when and the repo's skills; (3) protected paths are defined by `.github/CODEOWNERS` and enforced by branch protection with required code owner review, so only the human merges a PR that touches one; (4) agents merge their own PR only when it touches no protected path, after the required CI checks are green and the reviewer approved, and only after a trial of 5 consecutive PRs that touch no protected path in which the reviewer's verdict and the human's decision agree (the exact merge conditions are the plan's Decision 7; GitHub's "Allow auto-merge" setting stays off); (5) for each epic the agents loop implement, test and review on their own and the human does one final end-user test; (6) a short list of manual device checks remains (real GPS, Live Activity, notifications, permissions, Google Maps rendering) and is done before releases, not per PR; that list is the Tier 2 categories of `tm-pr-workflow` ("Tier 2: what automated tests cannot show"), not a separate list.
- Refs: `docs/epics/agentic-dev-loop.md`; `scripts/pre-push-check.sh`; `.github/workflows/ci.yml`; `.claude/skills/tm-pr-workflow`; `.claude/skills/epic-orchestration`.

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

### test-koin-graph
- Type: task
- Area: shared
- Order: 50
- Source: plan `protected-paths-review-2`, Q4, 2026-10-07
- Problem: no test verifies the Koin graph that `initKoin` and the platform modules build (`shared/src/commonMain/.../di/KoinInit.kt`, `PlatformModules.android.kt`, `PlatformModules.ios.kt`, and the `data/.../di/` modules they include). `koin-test` is in the catalog and no module uses it, so a missing or wrong binding fails only at app start; the same gap exists in the already open `data/.../di/`.
- Done when: a test builds the graph on each platform with fakes for the platform pieces and fails when a binding is missing, shown failing on a deliberately broken graph; the dependency it adds is named in the task (`shared/build.gradle.kts` is protected, so the human merges that PR).
- Refs: `docs/epics/protected-paths-review-2.md` (F5, Q4); `shared/src/commonMain/kotlin/dev/roozbahani/trailmetrics/shared/di/KoinInit.kt`; `shared/src/iosMain/kotlin/dev/roozbahani/trailmetrics/shared/di/KoinHelper.kt`; `shared/build.gradle.kts`; `gradle/libs.versions.toml` (`koin-test`).

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

### release-build-links-debug-xcframework
- Type: task
- Area: iosApp, shared
- Order: 105
- Source: docs/epics/ios-ui-tests.md Q9 (PR #138), 2026-10-13
- Problem: `iosApp/Packages/SharedKit/Package.swift` points its `binaryTarget` at `shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework` for every build configuration, and `scripts/build-kmp-framework.sh` builds only the debug XCFramework (`:shared:assembleTrailMetricsSharedDebugXCFramework`). So a Release build of the app links the debug Kotlin framework, which contains the Swift test support (`shared/src/iosMain/.../testsupport/SwiftTestSupport.kt`). The iOS UI-test fakes are not in it: since the plan's rewrite of 2026-10-13 they are built only into a test-only variant of the framework (`docs/epics/ios-ui-tests.md`, D1).
- Done when: a Release app build links a release XCFramework that contains no test-support or UI-test code, shown by a command in the PR (for example a symbol check on the Release app binary), and the gate and CI still build and test with the debug XCFramework.
- Refs: `iosApp/Packages/SharedKit/Package.swift`; `scripts/build-kmp-framework.sh`; `shared/build.gradle.kts` (`binaries.framework`); `shared/src/iosMain/kotlin/dev/roozbahani/trailmetrics/shared/testsupport/SwiftTestSupport.kt`; `docs/epics/ios-ui-tests.md` (F4, D1, Q9); `.claude/skills/tm-ios/SKILL.md` ("Build integration"); record `swift-test-support-ships-in-production-framework`.

### maps-empty-api-key-crashes-route-tab
- Type: task
- Area: iosApp/Route
- Order: 108
- Source: docs/epics/ios-ui-tests.md S0 spike, 2026-10-13
- Problem: `TrailMetricsApp.init()` configures the Maps SDK only when the key read from the app's Info.plist is not empty, but `RouteMapView.makeUIView` creates a `GMSMapView` regardless. With an empty key the app aborts when the Route tab appears (`+[GMSServices checkServicePreconditions]` raises from `-[GMSMapView initWithOptions:]`), so anyone who builds the app without a Maps key (a new contributor, a CI job without the placeholder) gets a crash, not a message. Found in the S0 spike; reproduced with empty build-setting overrides, 5 of 5 launches crashed.
- Done when: launching the app with an empty Maps key does not crash, and the Route tab shows a plain message instead of the map (the wording and whether other tabs stay usable are agreed with the human before implementation), shown by a test that launches without a key (a UI test once the iOS UI-test target exists, otherwise a unit/snapshot test of the decision "key present or not").
- Refs: `iosApp/TrailMetrics/TrailMetricsApp.swift`; `iosApp/Packages/Route/Sources/Route/RouteMapView.swift` (`makeUIView`); `RouteMapConfiguration`; `docs/epics/ios-ui-tests.md` (risks).

### classify-changes-self-test-failed-once
- Type: task
- Area: scripts
- Order: 118
- Source: PR for detekt-skips-kmp-source-sets
- Problem: `scripts/classify-changes.sh --self-test` failed once in a local gate run ("change classification self-test": 22 of 23 fixtures passed, the `usage-error` fixture reported "missing: usage error") before any commit of that branch was pushed. The next gate run passed, it passed on a clean `main`, and 30 consecutive reruns on the branch's clean tree did not reproduce it. The cause is unknown.
- Done when: the cause is found and fixed in the self-test or its fixtures (for example, the fixture depending on the timing or the stderr of the usage message), or a longer run under load shows it cannot recur and the record is deleted with that evidence in the PR.
- Refs: `scripts/classify-changes.sh` (`--self-test`, the `usage-error` fixture); `scripts/pre-push-check.sh` (change classification self-test step).

### tracking-finish-unsaved-snapshot-files-not-deleted
- Type: task
- Area: androidApp/feature-tracking
- Order: 125
- Source: PR from bugfix/tracking-finish-single-snapshot, 2026-10-07
- Problem: `TrackingScreen`'s Finish button requests no second `map.snapshot { }` while one is pending, but the guard is released when the callback fires, before the save ends. A Finish tap after the snapshot arrived while the save is still running requests a new snapshot and writes a second `activity_<millis>.png`, which `TrackingViewModel.finish` ignores (`isSessionSaved`), so nothing references or deletes it. A save that fails also leaves its snapshot file behind, and the retry writes a new one. `TrackingScreenSnapshotTest`'s slow-save test ("a double tap on Finish whose first save is slow saves one activity") takes this path and does not count the files.
- Done when: a Finish whose snapshot file ends up referenced by no saved activity (ignored by the ViewModel, or its save failed) leaves no file in `filesDir`, with a test that counts the files after a tap during a slow save and after a failed save followed by a successful retry.
- Refs: `androidApp/feature-tracking` `TrackingScreen` (the Finish button), `util/MapSnapshotSaver.kt` (`saveSnapshotToFile`), `TrackingViewModel.finish`, `TrackingScreenSnapshotTest`.

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

### swiftlint-optional-try-rule-selftest
- Type: task
- Area: iosApp, scripts
- Order: 192
- Source: agentic-dev-loop run 18 review (PR #104), 2026-10-05
- Problem: the custom rule `optional_try` in `iosApp/.swiftlint.yml` is turned off without failing `swiftlint lint --strict` if its `excluded_match_kinds` contains a name the installed SwiftLint does not know: SwiftLint only prints the warning "Invalid configuration for 'optional_try' rule. Falling back to default." and reports no `try?` at all (seen with SwiftLint 0.65.1 on a fixture: exit 0, 0 violations). CI's `ios-main` job installs SwiftLint with an unpinned `brew install swiftlint` (on PR #104's run it poured `swiftlint--0.65.1` from Homebrew, so the runner did not already have it, although `LEARNINGS.md` says SwiftLint ships preinstalled on `macos-latest` and needs no install step), so a new SwiftLint version could disable the rule silently. Nothing in the repository would notice.
- Done when: a committed check (a script with fixtures, in the style of the existing self-tests: one fixture dir per case, a `--self-test`, fail loudly never skip) lints fixture Swift files and shows that an unannotated `try?` fails, an annotated one passes, `try?` inside a comment and a string passes, and that the check fails if SwiftLint prints an invalid-configuration message; it runs in `scripts/pre-push-check.sh` and in CI's `ios-main` job (a workflow change: its PR must say so and authorize it), the PR states whether SwiftLint is pinned in CI or why not, and the `LEARNINGS.md` line about SwiftLint being preinstalled matches what CI does.
- Refs: `iosApp/.swiftlint.yml`; `.github/workflows/ci.yml` (`ios-main` job, steps "Install SwiftLint" and "Run SwiftLint"); `tm-ios` ("SwiftLint"); `LEARNINGS.md` (SwiftLint on `macos-latest` runners); PR #104.

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

### tracking-finish-without-profile-silent
- Type: task
- Area: androidApp/feature-tracking, iosApp/Tracking
- Order: 198
- Source: bugfix/android-persistence-errors-handled PR, 2026-10-05
- Problem: On both platforms the tracking screen's Finish returns without saving, without an event and without a message when no user profile is loaded (Android `TrackingViewModel.finish`: `_userProfile.value?.weightKg ?: return`; iOS `onFinishClicked`: `guard let userProfile = loadedUserProfile else { return }`). Since that PR the failed profile load itself is shown once as a general error, but a later Finish tap still does nothing visible, and the profile is never read again for that screen, so the session can't be saved.
- Done when: a Finish without a loaded profile on either platform either reads the profile again before saving or tells the user why nothing was saved (through the screen's existing error event), with a ViewModel test per platform; a Finish tap while the profile is still loading keeps working as today.
- Refs: `androidApp/feature-tracking` `TrackingViewModel` (`finish`, init); `iosApp/Packages/Tracking/Sources/Tracking/TrackingViewModel.swift` (`onFinishClicked`); `tm-kmp-shared` ("`@Throws` policy", rules 4 and 5).

### skill-changes-digest-self-test
- Type: task
- Area: scripts
- Order: 199
- Source: protected-paths-review S4 (open reference skills PR), 2026-10-06
- Problem: `scripts/skill-changes-digest.sh` (the human-run digest of skill and `CLAUDE.md` changes on `origin/main`) has no self-test, so a regression in its date validation, its first-parent commit selection or its `+`/`-` line filter would go unnoticed until the human runs it. The gate and CI files were outside S4's `allowed_paths`, so it was shown by hand only.
- Done when: a `--self-test` builds a scratch git repository with an `origin/main` ref and checks the commit selection (first parent, since a date, oldest first, only `.claude/skills/` and `CLAUDE.md` paths), the changed-line output, the no-changes line, and exit 2 with the usage for a bad date and an unknown option; it runs on bash 3.2; the gate and CI's `android` job run it like the other script self-tests; it was shown failing against a deliberately broken version.
- Refs: `scripts/skill-changes-digest.sh`; `scripts/pre-push-check.sh`; `.github/workflows/ci.yml`; `.claude/skills/tm-pr-workflow/SKILL.md` ("Tier 1").

### swift-test-support-ships-in-production-framework
- Type: task
- Area: shared, iosApp
- Order: 210
- Source: S1a spike of `docs/epics/ios-ui-tests.md`, 2026-10-13
- Problem: `shared/src/iosMain/kotlin/dev/roozbahani/trailmetrics/shared/testsupport/SwiftTestSupport.kt` ("TEST SUPPORT ONLY") is compiled into the production `TrailMetricsShared.xcframework`, because the Swift package tests link that framework and a second Kotlin framework cannot share its types; so every app build contains it. The S1a spike reported that a test-only variant of the framework (a separate module with the same `baseName`, copied over the debug path) builds and links, and the iOS UI-test epic adopts that mechanism for its seam, so the Swift test support could move there too. Low priority. Reported by the spike, not re-run; the task's first step is to verify that the package tests can link the variant.
- Done when: no test-only Kotlin is in the production framework (a `strings` or symbol check on the production framework in the PR), and the Swift package tests still pass in the gate and CI.
- Refs: `shared/src/iosMain/kotlin/dev/roozbahani/trailmetrics/shared/testsupport/SwiftTestSupport.kt`; `iosApp/Packages/TestSupport`; `scripts/build-kmp-framework.sh`; `docs/epics/ios-ui-tests.md` (F4, D1); record `release-build-links-debug-xcframework`.

### ios-ui-route-generate-twice-failed-on-main
- Type: task
- Area: iosApp/TrailMetricsUITests
- Order: 220
- Source: CI run 39049148407 (main, push, head 46a3636, the merge of #161), 2026-10-17
- Problem: `iOS — run UI tests` (since renamed `iOS 3 — run UI tests (after 2a)`) failed (exit 65) twice on `main`, in two Route tests, with the same message "Generate button not enabled after 3 waypoints" (the 10 s wait for `isEnabled` timed out in the same `XCTAssertEqual` of `XCUIApplication+RouteMap.swift`): `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce` (run 39049148407: test about 160 s, step about 802 s) and `RouteGenerateThenResetUITests.test_resetWhileGenerating_leavesACleanScreen` (run 39074545852: test about 92 s, step 510 s); the other five tests passed in both. #161 changed only comments in `scripts/classify-changes.sh` and `scripts/pre-push-check.sh` and one fixture `expect` line, and #162 only two skills and the epic text; none is an input of the iOS jobs. The cause is unknown. A slow runner or map is a hypothesis that the timings support but do not prove: in the first run the `route.map` check took about 77 s and the map presses 3 to 12 s; in the second the check took about 1 s and one of three presses took about 39 s (the others 8 and 4 s). The first suite started 302 s and 195 s after `xcodebuild` in the two failed runs and 126 to 357 s in the ten executions of the last 100 runs of `ci.yml`, so a late start does not tell failing runs from passing ones. In those 100 runs the job ran its tests 10 times (6 on `main`, 4 on PR branches, all four green; 5 more were skipped or cancelled) and failed 2, both on `main`, both Route tests; the step took 370 to 802 s; 3 of the 60 test executions took over 100 s (143 s `deleteConfirmedTwice`, 135 s `resetWhileGenerating`, 160 s the first failure). Before the split the same step ran 23 times in the single iOS job; one of those failed after 72 s (2026-10-14, not investigated). The two result bundles show that at the failure the screen had no red waypoint marker and Generate was disabled, so fewer than 3 waypoints existed; which press was lost, and why, is unknown. The log has no `GMS`, network or tile line. The location-permission alert appears in `RouteGenerateThenResetUITests` in every run (it is the first Route test), so it is not the cause by itself. The helper `addRouteWaypoints` reported any press problem as "Generate button not enabled"; since the change `test(ios-ui): make the Route map-press failures say which press was lost` it reports the press (k of N), the waypoint count the app showed, the press timings and a screenshot, so the next red run will say which press was lost. Risk noted: the Route tests depend on the location-permission state left by an earlier test (the tests run alphabetically and the alert appears only in the first Route test). A third failure came with run 39137921296 (the push of the #167 merge to `main`): `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce` failed with "map press 1 of 3 did not add a waypoint: count 0, expected 1 (press took 12.55 s, 23.50 s since the helper began)". The earlier two failures had no per-press diagnostic, so it is unproven that they were press 1. The result bundle of the third failure shows the map blank with no tiles, no permission alert or other overlay, the green start pin, no red waypoint marker, the probe overlay reading `waypoints=0` after two refreshes (so the app was responsive), Generate visible and disabled, and the press point clear of every overlay. The log shows the app launch to the automation session taking 56.5 s (29 s in the first test of that run) and the synthesized press event taking about 8 s; there is no XCUITest error, no interrupting element and no Maps, network or tile line. Counts: 2 failures in the 11 executions that ran tests before the diagnostics and 1 failure in the 4 executions after them (1 lost press in 12 helper calls). Press durations of passing helper calls range from about 1.6 s to 42 s, so a slow press alone does not separate failing from passing. Hypotheses: a load-related loss of the press is probable, not proven (there is no app-side evidence that the event reached the map); that the map's gesture handling was not ready although `route.map` exists is unknown (there is no app-side signal); that `didLongPressAt` is a no-op in some state is not supported by the code (it has no state guard); an alert or overlay is ruled out for this execution. The "use your location?" system alert appears once per execution and is dismissed by the default interruption handler; its origin was not found (UI-test mode replaces the location repository by a fake). The change `test(ios-ui): add Route waypoints through a seam, keep one map long-press test` makes three tests (`RouteGenerateTwiceUITests`, `RouteGenerateThenResetUITests`, `TrackingFinishTwiceUITests`) add their waypoints through the probe's seam button and keeps one test, `RouteMapLongPressUITests`, on the real long press: the dependency of the other three on the press is gone, the press path itself is not fixed, and the cause stays unknown. Two later red runs were app launch timeouts in the first Details tests, not this flake (in the last 100 runs of `ci.yml` the UI-test job ran its tests 36 times: 31 green, 5 red, 3 of them this Route flake and 2 launch timeouts); they are in the record `ios-ui-launch-timeout-on-ci`.
- Done when: the failure is explained, or it has recurred often enough that a human decides what to change.
- Refs: CI runs 39049148407 and 39074545852; `RouteGenerateTwiceUITests.test_generateTwice_requestsDirectionsOnce`; `RouteGenerateThenResetUITests.test_resetWhileGenerating_leavesACleanScreen`; CI run 39137921296; `RouteMapLongPressUITests.test_longPress_addsAWaypoint`; `iosApp/TrailMetricsUITests/Route/XCUIApplication+RouteMap.swift`; `docs/epics/ios-ui-tests.md` (D6); `.claude/skills/tm-testing/SKILL.md` ("Flakes (D6)").

### ios-ui-launch-timeout-on-ci
- Type: task
- Area: .github, iosApp/TrailMetricsUITests
- Order: 223
- Source: two red CI runs of the iOS UI-test job (a push to `main` and a pull request without iOS, data or test changes), 2026-10-20
- Problem: Both runs failed in the job `iOS 3 — run UI tests (after 2a)` (exit 65) because the first Details test, `DetailsDeleteTwiceUITests`, timed out launching the app in its Set Up ("Timed out while launching application via Xcode", 73.5 s and 80.9 s). In the second run `DetailsFailedDeleteUITests` also failed to launch ("Failed to get background assertion for target app", 43.0 s, after "Failed to send signal 19" from the simulator launcher). No test body ran and the three Route tests passed. Runner image, Xcode and simulator were the same as in seven green runs; in the first test of green runs the automation-session setup took 5.9 to 56.4 s against a limit of about 60 s. In the last 100 runs of `ci.yml` the job ran its tests 36 times: 31 green, 5 red (3 the Route flake of `ios-ui-route-generate-twice-failed-on-main`, 2 these launch timeouts). The merged change of the `main` run cannot reach the network client in UI-test mode. Reading: a launch stall on the runner, about 80% sure, not proven; the logs do not say whether the runner or the simulator was slow. The step booted nothing itself (`xcodebuild` booted the simulator on its own and nothing waited for it); it now boots it with `simctl bootstatus -b`, waits, and prefixes every `xcodebuild` output line with a UTC time, so the next red run shows where the time went. No retry and no longer timeout (D6).
- Done when: over the next 30 executions of the UI-test job on `main` and on PRs no launch timeout occurs, or the new timestamps name the slow phase and that is fixed.
- Refs: `.github/workflows/ci.yml` (job `ios-ui`, step "Run iOS UI tests"); `iosApp/TrailMetricsUITests/Support/XCUIApplication+Scenario.swift`; `ios-ui-route-generate-twice-failed-on-main`; `docs/epics/ios-ui-tests.md` (D6).

### ios-ui-location-permission-alert-origin
- Type: task
- Area: iosApp/TrailMetricsUITests
- Order: 225
- Source: board record ios-ui-route-generate-twice-failed-on-main and chat 2026-10-18
- Problem: The "use your location?" system alert has so far been seen only in CI logs or result bundles, not locally. A local look found no origin: the production `IosLocationRepositoryImpl` is ruled out (the UI-test module overrides all five bindings that would create it, and `UiTestEntryTest` asserts it is never created in UI-test mode), no Swift file requests location, and on a fresh local simulator (iPhone 17, iOS 26.5, privacy reset, app uninstalled) the alert did not appear in `RouteGenerateTwiceUITests` alone or in the three Route classes run in order; a temporary interruption monitor never fired. The Route tests may still depend on the permission state an earlier test left. The CI logs read since then show the alert in every UI-test log (red and green), only in `RouteGenerateThenResetUITests`, the first Route test, about 9 to 10 s into the test, and the default interruption handler dismisses it with "Don't Allow". It does not appear in the Details tests that run before it, so something in the Route screen's start triggers it; the origin is still not found.
- Done when: the alert is captured on CI (an interruption monitor in the Route tests that records its label, or a failing run's result bundle), and the Route tests no longer depend on which ran first, either by `XCUIApplication.resetAuthorizationStatus(for: .location)` before launch or by handling the alert explicitly in each Route test. If CI's simulator itself needs a reset step, that touches the protected CI workflow and the human decides.
- Refs: `RouteGenerateThenResetUITests` and the other Route tests; `iosApp/TrailMetricsUITests/Route/XCUIApplication+RouteMap.swift`.

## Drift

### data-kover-comment-stale-figure
- Type: drift
- Area: data
- Order: 230
- Source: PR for location-current-swallows-cancellation
- Problem: The comment above the Kover floor in `data/build.gradle.kts` gives the measured coverage as 44.38% (142/320 lines). With `AndroidLocationRepositoryImplTest` the `data` host report measures 49.38% (160 of 324 lines) and the floor in `config/kover-floors.properties` is 48. `data/build.gradle.kts` is a protected path, so the comment was left as it is.
- Done when: the comment states the current measured figure, or no longer quotes one, in a PR that may touch the protected path.
- Refs: `data/build.gradle.kts` (Kover floor comment); `config/kover-floors.properties`.
