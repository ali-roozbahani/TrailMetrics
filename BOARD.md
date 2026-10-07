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
- Done when: a human-approved plan under `docs/epics/` comes first. Then: (1) a deterministic test seam (fakes for location, directions and storage injectable at app launch) and UI-test targets exist on iOS (XCUITest) and Android (Compose UI tests), with a fast smoke subset in the local gate when the diff touches UI or ViewModels and the full UI suite in CI; (2) an independent reviewer agent with a fresh context reviews every PR from git against the task's Done when and the repo's skills; (3) protected paths are defined by `.github/CODEOWNERS` and enforced by branch protection with required code owner review, so only the human merges a PR that touches one; (4) agents merge their own PR only when it touches no protected path, after the two required CI checks are green and the reviewer approved, and only after a trial of 5 consecutive PRs that touch no protected path in which the reviewer's verdict and the human's decision agree (the exact merge conditions are the plan's Decision 7; GitHub's "Allow auto-merge" setting stays off); (5) for each epic the agents loop implement, test and review on their own and the human does one final end-user test; (6) a short list of manual device checks remains (real GPS, Live Activity, notifications, permissions, Google Maps rendering) and is done before releases, not per PR.
- Refs: `docs/epics/agentic-dev-loop.md`; `scripts/pre-push-check.sh`; `.github/workflows/ci.yml`; `.claude/skills/tm-pr-workflow`; `.claude/skills/epic-orchestration`; board `test-ios-ui-double-tap-and-stale-results`.

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

### android-route-error-snackbar-covers-generate
- Type: task
- Area: androidApp/feature-route
- Order: 95
- Source: Route screen Compose UI tests PR, 2026-10-06
- Problem: On the Route screen, `RouteScreen`'s `SnackbarHost` (the `Scaffold`'s) lies over the Generate button at the bottom of the content: in `RouteScreenTest` (411x891 dp) the snackbar of a failed directions call spans the bottom of the screen across the button, and a tap on Generate while it shows does not reach the button (the directions fake gets no second request). After a failed Generate the user can retry only once the snackbar's short duration (4 s) has passed. Found by the Compose UI test, not checked on a device.
- Done when: after a failed directions call, Generate can be tapped while the error snackbar is shown (for example the snackbar placed so it does not cover the bottom controls), with a `RouteScreenTest` case that taps Generate while the snackbar is still on screen and gets a second request; `RouteScreenRobot.waitForSnackbarToHide` is then no longer needed by the failure test.
- Refs: `androidApp/feature-route` `RouteScreen` (`Scaffold` `snackbarHost`, the bottom `Column` with the Generate button); `RouteScreenTest` (`a failed directions call shows the error and Generate can be tapped again`), `RouteScreenRobot.waitForSnackbarToHide`.

### android-error-snackbar-covers-start-buttons
- Type: task
- Area: androidApp/feature-tracking, androidApp/feature-route
- Order: 97
- Source: PR from bugfix/screen-events-not-blocked-by-snackbar, 2026-10-07
- Problem: The error snackbar takes the taps meant for a start button below it, as `android-route-error-snackbar-covers-generate` describes for Generate. On the Tracking screen, `TrackingScreen`'s `SnackbarHost` lies over Start: in `TrackingScreenTest` (411x891 dp), with the error of a failed profile read shown, a tap on Start does not start the session, so the user can start only once the snackbar's short duration (4 s) has passed. On the Route screen the same happens to the panel's Start Tracking button: a tap on it while the error of a failed profile read is shown does not reach the ViewModel. Found by the Compose UI tests, not checked on a device.
- Done when: Start (Tracking) and Start Tracking (Route) can be tapped while an error snackbar is shown, with a Compose UI test per screen that taps the button while the snackbar is on screen and sees the session start (Tracking) or tracking start (Route); `RouteScreenRobot.startTrackingThroughViewModel` is then no longer needed by the tests that use it.
- Refs: `androidApp/feature-tracking` `TrackingScreen` (`Scaffold` `snackbarHost`, the Start button); `androidApp/feature-route` `RouteScreen` (`Scaffold` `snackbarHost`, the Start Tracking panel); `TrackingScreenTest` (`two errors in a row are shown one after the other in order`, which holds the profile read for this reason), `RouteScreenRobot.startTrackingThroughViewModel`.

### test-ios-ui-double-tap-and-stale-results
- Type: task
- Area: iosApp
- Order: 100
- After: agentic-dev-loop
- Source: bugfix/ios-history-details-delete-and-load-errors PR
- Problem: The iOS ViewModel guards for a repeated Finish (`TrackingViewModel.onFinishClicked`), a repeated delete confirmation (`DetailsViewModel.onDeleteConfirmed`), a repeated Generate (`RouteViewModel.onGenerateRouteClicked`) and Generate followed by Reset (`onResetClicked`) are covered by Swift unit tests in the packages, but nothing proves the Views deliver such taps to the ViewModel the way the tests do, and they can't be checked reliably by hand. The Android equivalents are done: the Compose UI tests of `feature-history`, `feature-route` and `feature-tracking` cover them under Robolectric. There is no iOS UI-test target today: `TrailMetrics.xcodeproj` has only the `TrailMetrics` app and the `TrackingWidget` extension, and the shared `TrailMetrics` scheme has no testables. Design note: XCUITest drives the real app, so it needs deterministic fakes (location, directions, storage) injected at app launch (a launch argument read by the composition root, or a Koin override in `doInitKoinIos`); that seam doesn't exist yet and is part of this task.
- Done when: a UI-test target exists in the shared scheme with a launch-time fake seam, and XCUITest scenarios cover: Finish tapped twice (one History entry), Generate then Reset (no route afterwards), Generate tapped twice (one directions request), delete confirmation tapped twice (one deletion), and a failed delete showing the "Error" alert.
- Refs: `iosApp/TrailMetrics.xcodeproj`; `TrailMetricsApp` (`doInitKoinIos`), `KoinHelper`; `TrackingView`/`TrackingViewModel.onFinishClicked`; `RouteView`/`RouteViewModel.onGenerateRouteClicked`, `onResetClicked`; `DetailsView`/`DetailsViewModel.onDeleteConfirmed`; `HistoryView`.

### tracking-camera-update-without-maps-initialized
- Type: task
- Area: androidApp/feature-tracking
- Order: 112
- Source: Tracking screen Compose UI tests PR, 2026-10-07
- Problem: `TrackingScreen`'s `LaunchedEffect(state.currentPath)` calls `CameraUpdateFactory.newLatLng` on every path change, whether or not a map exists. `CameraUpdateFactory` works only after `MapsInitializer` has filled it from Google Play services (normally when the `MapView` is created); before that it throws `NullPointerException` ("CameraUpdateFactory is not initialized"). Without a fake factory, 15 of the 26 `TrackingScreenTest` cases (map not rendered) fail with that exception. On a device where the Maps SDK cannot initialize (Google Play services missing, disabled or outdated), the first location fix after Start would therefore throw inside the effect. Found while writing the tests, not reproduced on a device.
- Done when: a path change without an initialized Maps SDK neither throws nor stops tracking (for example the camera update is built only once the map is there, as `cameraPositionState.animate` already waits for it), shown by a Compose UI test that does not install the fake factory.
- Refs: `androidApp/feature-tracking` `TrackingScreen` (`LaunchedEffect(state.currentPath)`); `TrackingScreenTest`, `fakes/FakeGoogleMap.kt` (`installFactories`).

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

### directions-http-status-ignored
- Type: task
- Area: data
- Order: 150
- Source: PR #70
- Problem: `networkModule`'s `HttpClient` doesn't set `expectSuccess`, and neither `safeApiCall` nor `DirectionsRepositoryImpl.getClosedRoute` checks the HTTP status. A 4xx/5xx response whose body is a valid `DirectionsResponseDto` with status "OK" returns a successful route. A non-2xx response with a non-JSON body fails only through deserialization, so the HTTP status never reaches the `DirectionsApiError` cause. Pinned by `DirectionsRepositoryImplTest` "HTTP error status with a valid OK body currently returns a successful route".
- Done when: a non-2xx Directions response returns `RouteError.DirectionsApiError` whose cause names the HTTP status, and that pinned test is changed to assert it.
- Refs: `data` `di/NetworkModule.kt`, `common/SafeApiCall.kt`, `DirectionsRepositoryImpl.getClosedRoute`; `DirectionsRepositoryImplTest`.

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

### document-ios-start-after-stop-limitation
- Type: task
- Area: docs, iosApp
- Order: 180
- Source: audit + chat 2026-10-01
- Problem: iOS `TrackingViewModel.onStopClicked` cancels and clears `stateObservationTask` and `locationIssuesObservationTask`, which are only started from `init`. A second `onStartClicked` on the same instance would therefore not observe state. Users can't hit this today, because every Stop path leaves the screen first: in-app Stop (controls row and exit alert) calls `dismiss()`, Live Activity Stop (`handleStopNotification`) emits `.dismissed`, and auto-completion shows `finishCard` instead of the controls. Document it as a known limitation; don't fix it.
- Done when: documented in `tm-ios` or `LEARNINGS.md`.
- Refs: iOS `TrackingViewModel.onStopClicked`, `onStartClicked`, `observeTrackingState`, `handleStopNotification`; `TrackingView` (`controlsRow`, `finishCard`, `.dismissed` handling).

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
- Problem: the custom rule `optional_try` in `iosApp/.swiftlint.yml` is turned off without failing `swiftlint lint --strict` if its `excluded_match_kinds` contains a name the installed SwiftLint does not know: SwiftLint only prints the warning "Invalid configuration for 'optional_try' rule. Falling back to default." and reports no `try?` at all (seen with SwiftLint 0.65.1 on a fixture: exit 0, 0 violations). CI's `ios` job installs SwiftLint with an unpinned `brew install swiftlint` (on PR #104's run it poured `swiftlint--0.65.1` from Homebrew, so the runner did not already have it, although `LEARNINGS.md` says SwiftLint ships preinstalled on `macos-latest` and needs no install step), so a new SwiftLint version could disable the rule silently. Nothing in the repository would notice.
- Done when: a committed check (a script with fixtures, in the style of the existing self-tests: one fixture dir per case, a `--self-test`, fail loudly never skip) lints fixture Swift files and shows that an unannotated `try?` fails, an annotated one passes, `try?` inside a comment and a string passes, and that the check fails if SwiftLint prints an invalid-configuration message; it runs in `scripts/pre-push-check.sh` and in CI's `ios` job (a workflow change: its PR must say so and authorize it), the PR states whether SwiftLint is pinned in CI or why not, and the `LEARNINGS.md` line about SwiftLint being preinstalled matches what CI does.
- Refs: `iosApp/.swiftlint.yml`; `.github/workflows/ci.yml` (`ios` job, steps "Install SwiftLint" and "Run SwiftLint"); `tm-ios` ("SwiftLint"); `LEARNINGS.md` (SwiftLint on `macos-latest` runners); PR #104.

### swiftlint-disable-requires-reason-rule
- Type: task
- Area: iosApp
- Order: 194
- Source: agentic-dev-loop run 18 review (PR #104), 2026-10-05
- Problem: the repo's convention is `// swiftlint:disable:next <rule> - <reason>`, but a disable comment with no reason, or with an empty one (` - ` and nothing after it), still passes `--strict` (seen with SwiftLint 0.65.1 on a fixture: exit 0, 0 violations); only review notices.
- Done when: a check rejects a `swiftlint:disable` comment (any rule, `:next`, `:this`, `:previous` and the block forms) that has no ` - <reason>` text, every existing suppression under `iosApp/` complies or the PR lists the ones that do not with the human's decision, and the check is shown failing on an example without a reason and passing with one (a SwiftLint custom rule on comments, or a small script, whichever the PR justifies).
- Refs: `iosApp/.swiftlint.yml`; `tm-ios` ("SwiftLint", suppression convention); board `drift-suppress-comments`.

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
- Problem: `check-kover-floors.py`, `check-protected-paths.py`, `check-pr-review-workflow.py` and `classify-changes.sh` build scratch git repositories and commit in them without `gc.auto=0` and `maintenance.auto=false`, and remove them with a bare `tempfile.TemporaryDirectory` or `rm -rf`; `check-ios-scope.py` has `gc.auto=0` but not `maintenance.auto=false`. The same "Directory not empty" failure that once stopped the skill rule-change self-test in CI could hit any of them.
- Done when: each gets the same git flags and the same resilient cleanup as `check-skill-rule-changes.py` (or one shared approach the human agrees), with its self-test still passing.
- Refs: `scripts/check-kover-floors.py`; `scripts/check-protected-paths.py`; `scripts/check-pr-review-workflow.py`; `scripts/classify-changes.sh`; `scripts/check-ios-scope.py`; `scripts/check-skill-rule-changes.py` (`remove_scratch`).

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

## Drift

### drift-suppress-comments
- Type: drift
- Area: androidApp, data
- Order: 200
- Source: chat 2026-10-01
- Problem: Several suppressions have no reason next to them: `@Suppress("LocalContextGetResourceValueCall")` on the events `LaunchedEffect` in `TrackingScreen` and `RouteScreen`; `@Suppress("UnusedPrivateMember")` on `RouteScreen`'s `ActivityTypeSelectorPreview` (its siblings have the preview comment); `@Suppress("TooGenericExceptionCaught")` on `safeApiCall` and twice in `AndroidLocationRepositoryImpl`. Every iOS `swiftlint:disable` has a reason. Whether any existing reason is stale was not checked.
- Done when: every suppression has an accurate reason, or is removed.
- Refs: `TrackingScreen`, `RouteScreen` (feature-tracking, feature-route); `data` `safeApiCall`, `AndroidLocationRepositoryImpl`.

### drift-pr-review-log-env-prints-pr-body
- Type: drift
- Area: .github
- Order: 230
- Source: agentic-dev-loop run 8 (PR #94), 2026-10-04
- Problem: the comment above the step "Build review inputs" in `.github/workflows/pr-review.yml` says "Nothing here prints PR or model text to the log, where it could act as a workflow command". The runner prints each step's `env:` block at the top of the step's log, and that step's `env:` carries `PR_BODY` (the PR description) and `HEAD_REF` (the author's branch name), so the PR description appears in that step's log. On PR #94 (run 37166301311) the body contained lines starting with `::error title=Review — pr-reviewer::`, and the check run still had only the titled `warning` and the untitled runner notice, so the runner did not process them as commands.
- Done when: the human has chosen between (a) correcting the comment to the real property (header lines are not processed as commands, shown by that run) and (b) not passing PR text through `env:` at all (for example reading it from the event payload with `jq`), and the choice is implemented and shown.
- Refs: `.github/workflows/pr-review.yml` (step "Build review inputs" and the comment above it); PR #94 review run 37166301311 (job "Review — pr-reviewer").

### drift-kmp-framework-script-header-outside-ci
- Type: drift
- Area: scripts
- Order: 240
- Source: agentic-dev-loop run 13 (PR #99 or the number this PR gets), 2026-10-05
- Problem: the header comment of `scripts/build-kmp-framework.sh` calls the script "The single entry point for that framework outside CI" and names only the scheme pre-action, the app target's build phase and `scripts/pre-push-check.sh` as callers. Since this PR, CI's `ios` job runs the script in its "Build KMP Shared Framework" step, so "outside CI" is stale. The file is a protected path, and a change to it matches the gate's iOS filter, so that change makes the gate's iOS steps required locally.
- Done when: the comment names CI's `ios` job as a caller and no longer says "outside CI", in a PR that the human authorizes for this protected file.
- Refs: `scripts/build-kmp-framework.sh` (header comment); `.github/workflows/ci.yml` (`ios` job, step "Build KMP Shared Framework").

### drift-learnings-ios-ci-explicit-gradle-step
- Type: drift
- Area: learnings
- Order: 250
- Source: agentic-dev-loop run 13 (PR #99 or the number this PR gets), 2026-10-05
- Problem: the `LEARNINGS.md` item under "Phase I — Enforcement (allWarningsAsErrors, Detekt, SwiftLint) and CI" says iOS CI builds the XCFramework before `xcodebuild` "via an explicit `./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework` step". Since this PR, that step runs `scripts/build-kmp-framework.sh`, so the item reads as stale. `LEARNINGS.md` is history, and its past entries are not rewritten.
- Done when: the human has chosen between adding a dated note to that item (CI runs the script since this PR) and leaving it as history, and the choice is implemented.
- Refs: `LEARNINGS.md` ("Phase I — Enforcement (allWarningsAsErrors, Detekt, SwiftLint) and CI", the iOS CI item); `.github/workflows/ci.yml` (`ios` job, step "Build KMP Shared Framework").

### drift-ci-ios-xcodebuild-logs-environment
- Type: drift
- Area: .github
- Order: 260
- Source: agentic-dev-loop run 16 (the PR that adds `scripts/scrub-env.sh`), 2026-10-05
- Problem: since that PR the local gate removes secret-looking variables (deny list in `scripts/scrub-env.sh`) from its environment before `xcodebuild` logs it; CI's `ios` job does not, and `.github/workflows/ci.yml` was not changed. Xcode prints the environment of the framework script's scheme pre-action and Run Script phase as `export NAME=...` lines. In the log of the job "iOS — SwiftLint, Build" of run 37297553551 (PR #101), 2305 lines contain `export ` (1748 distinct names), all in the step "Build iOS app". The exported names that match the deny list are 40 `GITHUB_*` names (for example `GITHUB_REPOSITORY`, `GITHUB_RUN_ID`, `GITHUB_SHA`, `GITHUB_OUTPUT`) and `GMS_API_KEY` (a build setting from the iOS secrets config, which CI fills with a placeholder; not masked). `ACTIONS_ORCHESTRATION_ID` and `ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE` are exported too (no deny-list match). No exported name contains `TOKEN`, `SECRET`, `PASSWORD` or `CREDENTIAL`. One export line is masked by GitHub as a whole (`export ***`), so its name is not visible.
- Done when: the human has decided how CI's `xcodebuild` steps ("Build iOS app", "Run iOS package tests") are protected (for example sourcing `scripts/scrub-env.sh` there, or leaving them as they are because the job holds no secret), and the decision is implemented and shown in a CI log, by names and counts only.
- Refs: `.github/workflows/ci.yml` (`ios` job, steps "Build iOS app" and "Run iOS package tests"); `scripts/scrub-env.sh`; `scripts/pre-push-check.sh`; run 37297553551 (job "iOS — SwiftLint, Build").

### drift-kover-comments-name-removed-board-slugs
- Type: drift
- Area: androidApp/feature-history, androidApp/feature-tracking
- Order: 330
- Source: protected drift cleanup PR (chore/protected-drift-cleanup), 2026-10-06
- Problem: the comment above the `kover` block in `androidApp/feature-history/build.gradle.kts` says the floor is a little below the module's measured line coverage "(79.15%, measured after test-feature-history-compose-ui)", and the one in `androidApp/feature-tracking/build.gradle.kts` "(30.02%, measured on main after test-feature-tracking)". Both name a board slug that is gone from `BOARD.md` and a measured figure that goes stale with the next test; the floor itself is each module's entry in `config/kover-floors.properties`. `androidApp/feature-route/build.gradle.kts` no longer names a figure. Both build files are protected paths outside this PR's scope.
- Done when: both comments stop naming a measured figure and a board slug, as `androidApp/feature-route/build.gradle.kts` does, keeping their sentence about how `config/kover-floors.properties` is read.
- Refs: `androidApp/feature-history/build.gradle.kts`, `androidApp/feature-tracking/build.gradle.kts` (comment above the `kover` block); `androidApp/feature-route/build.gradle.kts`; `config/kover-floors.properties`.

### drift-robolectric-users-omit-feature-tracking
- Type: drift
- Area: docs
- Order: 340
- Source: Tracking screen Compose UI tests PR, 2026-10-07
- Problem: `CLAUDE.md` ("Testing stack") says Robolectric is "used by `data` and by the Compose UI tests of `feature-history` and `feature-route`", and `README.md` says the same twice (the "Testing strategy" bullet and the Testing row of the stack table). Since that PR `feature-tracking`'s Compose UI tests (`TrackingScreenTest`, `TrackingScreenSnapshotTest`) and `MapSnapshotSaverTest` run under Robolectric too. `CLAUDE.md` is a protected path, and neither file was in that PR's `allowed_paths`.
- Done when: both files name `feature-tracking` among the Robolectric users (or name no module list at all), in a PR the human authorizes for `CLAUDE.md`.
- Refs: `CLAUDE.md` ("Testing stack"); `README.md` ("Testing strategy", the stack table's Testing row); `androidApp/feature-tracking/src/test`.

### drift-epic-plan-tier2-device-lines
- Type: drift
- Area: docs
- Order: 350
- Source: Tier 2 automated-first PR (chore/tier2-automated-first), 2026-10-07
- Problem: `docs/epics/mvi-presentation-migration.md` is a kept plan meant as a reference for future planning, and its `tier2:` lines for the three Android ViewModel subtasks are device checks by default ("Android emulator: plan a route ...", "Android emulator: History with 0 and 2+ activities ...", "Android emulator with a GPX/mock-location route ..."), as is its "Tier 2 on the integrated result" section. Since that PR, `tm-pr-workflow` ("Tier 2: what automated tests cannot show") and `epic-orchestration` make a `tier2:` line name the automated tests that cover the behavior, with a human check only for a stated reason, so a plan copied from this one would bring back the old default. `docs/` was outside that PR's allowed paths.
- Done when: the human has decided whether the kept plan stays as a historical record with a note that its `tier2:` lines predate the rule, or its `tier2:` lines are rewritten in the new shape (test names, or a human check with its reason).
- Refs: `docs/epics/mvi-presentation-migration.md` (`tier2:` of the Android ViewModel subtasks, "Tier 2 on the integrated result"); `.claude/skills/tm-pr-workflow/SKILL.md` ("Tier 2: what automated tests cannot show"); `.claude/skills/epic-orchestration/SKILL.md` ("Format").

### drift-agentic-dev-loop-manual-device-checklist
- Type: drift
- Area: docs
- Order: 360
- Source: Tier 2 automated-first PR (chore/tier2-automated-first), 2026-10-07
- Problem: `docs/epics/agentic-dev-loop.md` ("Out of scope") leaves "the manual device checklist" to a later epic, and the `agentic-dev-loop` record's Done when, item (6), keeps "a short list of manual device checks" done before releases, not per PR. Since that PR, `tm-pr-workflow` ("Tier 2: what automated tests cannot show") already defines when a human check is allowed (no automated test can observe it, with the categories real GPS, Maps SDK rendering, OS permission dialogs, the tracking notification and the Live Activity, and visual design; a missing seam or test target with its board record; the final smoke check) and has a PR list such checks as they arise. The plan and the record do not point to that rule. `docs/` was outside that PR's allowed paths, and the record is not that PR's to rewrite.
- Done when: the human has decided whether the plan's "Out of scope" line and the record's item (6) refer to `tm-pr-workflow`'s Tier 2 categories as the manual device checklist, or the checklist stays a separate release-time list, and the plan says which.
- Refs: `docs/epics/agentic-dev-loop.md` ("Out of scope"); `BOARD.md` `agentic-dev-loop` (Done when, item 6); `.claude/skills/tm-pr-workflow/SKILL.md` ("Tier 2: what automated tests cannot show").
