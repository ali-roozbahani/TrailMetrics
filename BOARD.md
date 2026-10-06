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
- Refs: `docs/epics/agentic-dev-loop.md`; `scripts/pre-push-check.sh`; `.github/workflows/ci.yml`; `.claude/skills/tm-pr-workflow`; `.claude/skills/epic-orchestration`; board `test-ios-ui-double-tap-and-stale-results`, `test-feature-tracking-compose-ui`, `test-feature-route-compose-ui`.

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

### auto-merge-requires-approve-verdict
- Type: task
- Area: .claude, .github
- Order: 45
- Source: agentic-dev-loop S3 PR, 2026-10-02
- Problem: The merge conditions and the reading of the CI verdict from the `Review — pr-reviewer` annotation are now written in the plan (Decisions 5, 7 and 8 of `docs/epics/agentic-dev-loop.md`) and in `tm-agent-loop` ("Reading the CI verdict", "Merge conditions"). The proof in S4b only observed a `warning` (`ESCALATE_TO_HUMAN`) annotation on a real PR; `notice` (`APPROVE`) and `failure` (`CHANGES`) were checked against fixtures only. S6's PR, which documents auto-merge for unprotected paths, could drift from those conditions or rely on a mapping never seen on a real PR.
- Done when: S6's PR states the same merge conditions as `tm-agent-loop` (head is a branch of this repository, author is the machine account, CI annotation `APPROVE` and recorded local verdict `APPROVE` for the head SHA, both required checks green, no protected path) and the same fail-closed annotation rule, and it is written only after a real `notice`/`APPROVE` annotation has been read from a PR with `tm-agent-loop`'s commands.
- Refs: `.claude/skills/tm-agent-loop/SKILL.md` ("Reading the CI verdict", "Merge conditions"); `.github/workflows/pr-review.yml` (job `Review — pr-reviewer`, step "Map verdict"); `docs/epics/agentic-dev-loop.md` (S6, Decisions 5, 7 and 8).

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

### android-route-start-tracking-repeated-navigation
- Type: task
- Area: androidApp/feature-route
- Order: 93
- Source: bugfix/ios-route-start-tracking-single-navigation PR
- Problem: Android's `RouteViewModel.startTracking` (`RouteAction.StartTrackingClicked`) has no guard against a repeated tap: each tap launches its own coroutine, and each sends `RequestUserProfile` or `NavigateToTracking` into the `Channel.BUFFERED` events channel once the profile read returns. `RouteRoot` collects that channel in a `LaunchedEffect`, so a second `NavigateToTracking` that arrives while RouteScreen is still composed navigates to Tracking twice, and one that arrives after it left composition stays in the channel and is delivered when RouteScreen is composed again, opening Tracking again on return. Two taps without a profile open the profile sheet twice (the second only sets `showProfileSheet` again). Found by reading the code, not reproduced; iOS got the equivalent guard in that PR.
- Done when: a repeated `StartTrackingClicked` while one is in flight sends at most one event (a guard like `generationJob` in `generateRoute`, released on every exit), with a JVM test that dispatches two `StartTrackingClicked` before the profile read returns and receives one `NavigateToTracking`, and one that a later, separate tap still works.
- Refs: `androidApp/feature-route` `RouteViewModel.startTracking`, `generateRoute` (the guard pattern), `RouteScreen` (`RouteRoot`'s event collection); iOS `RouteViewModel.onStartTrackingClicked`.

### document-ios-pending-events-shape
- Type: task
- Area: .claude/skills/tm-ios
- Order: 94
- Source: bugfix/ios-init-time-error-events-kept PR
- Problem: `tm-ios` ("ViewModel shape", the one-shot signals bullet) tells a new ViewModel to expose a `makeEventsStream()` factory that returns a new `AsyncStream` each time, pointing at `RouteViewModel`/`TrackingViewModel`. Both now also keep events emitted while no consumer is active (`pendingEvents`, at most 10, oldest dropped first) and deliver them to the next stream, because `yield` to a missing or terminated continuation loses them. The bullet is still accurate but doesn't say this, so a new screen written from the skill alone would lose init-time errors again. It is a protected path, so it was not changed in that PR.
- Done when: the bullet says that events emitted with no active consumer are kept and delivered to the next stream (checking `yield`'s result, bounded), pointing at `RouteViewModel.emit`.
- Refs: `.claude/skills/tm-ios/SKILL.md` ("ViewModel shape"); `RouteViewModel.emit`, `makeEventsStream`; `TrackingViewModel.emit`.

### test-ios-ui-double-tap-and-stale-results
- Type: task
- Area: iosApp
- Order: 100
- After: agentic-dev-loop
- Source: bugfix/ios-history-details-delete-and-load-errors PR
- Problem: The iOS ViewModel guards for a repeated Finish (`TrackingViewModel.onFinishClicked`), a repeated delete confirmation (`DetailsViewModel.onDeleteConfirmed`), a repeated Generate (`RouteViewModel.onGenerateRouteClicked`) and Generate followed by Reset (`onResetClicked`) are covered by Swift unit tests in the packages, but nothing proves the Views deliver such taps to the ViewModel the way the tests do, and they can't be checked reliably by hand. The Android equivalents are the three `test-feature-*-compose-ui` records. There is no iOS UI-test target today: `TrailMetrics.xcodeproj` has only the `TrailMetrics` app and the `TrackingWidget` extension, and the shared `TrailMetrics` scheme has no testables. Design note: XCUITest drives the real app, so it needs deterministic fakes (location, directions, storage) injected at app launch (a launch argument read by the composition root, or a Koin override in `doInitKoinIos`); that seam doesn't exist yet and is part of this task.
- Done when: a UI-test target exists in the shared scheme with a launch-time fake seam, and XCUITest scenarios cover: Finish tapped twice (one History entry), Generate then Reset (no route afterwards), Generate tapped twice (one directions request), delete confirmation tapped twice (one deletion), and a failed delete showing the "Error" alert.
- Refs: `iosApp/TrailMetrics.xcodeproj`; `TrailMetricsApp` (`doInitKoinIos`), `KoinHelper`; `TrackingView`/`TrackingViewModel.onFinishClicked`; `RouteView`/`RouteViewModel.onGenerateRouteClicked`, `onResetClicked`; `DetailsView`/`DetailsViewModel.onDeleteConfirmed`; `HistoryView`; board `test-feature-tracking-compose-ui`, `test-feature-route-compose-ui`.

### test-feature-tracking-compose-ui
- Type: task
- Area: androidApp/feature-tracking
- Order: 110
- Source: test-feature-tracking PR
- Problem: After the JVM tests, `feature-tracking`'s `TrackingViewModel`, `RouteCompletionTracker` and `di/TrackingUiModule` are fully covered; everything left is Android-framework code with 0% covered: `TrackingScreen` (284 lines: `TrackingRoot`'s event handling and permission flow, both `TrackingScreen` overloads, `MetricsDisplay`, the preview, `hasLocationPermission`) and `util/MapSnapshotSaver` (19 lines: `saveSnapshotToFile` scaling, PNG write and `IOException` path). They need Robolectric and/or compose-ui-test. The catalog already has `robolectric` (used by `data`), `androidx-compose-ui-test-junit4` and `androidx-compose-ui-test-manifest` (used by `androidApp/app` androidTest), but this module's test source sets don't depend on them yet. The JVM tests of the double-Finish fix (tracking-finish-saves-twice) can only dispatch two `Finish` actions back to back; the real UI path is asynchronous and untested.
- Done when: an explicit task adds the existing Robolectric/compose-ui-test catalog entries as this module's test dependencies, `TrackingScreen` and `saveSnapshotToFile` have tests, a double tap on the Finish button, including the asynchronous `map.snapshot` callback path in `TrackingScreen`, results in exactly one saved activity and one `Saved`, and the module's Kover floor is raised in the same PR.
- Refs: `androidApp/feature-tracking` `TrackingScreen`, `MetricsDisplay`, `util/MapSnapshotSaver.kt`; `androidApp/feature-tracking/build.gradle.kts` `minBound`; `tm-testing` ("Compose UI tests", "What's actually available today").

### test-feature-route-compose-ui
- Type: task
- Area: androidApp/feature-route
- Order: 130
- Source: test-feature-route PR
- Problem: After the JVM tests, `feature-route`'s `RouteViewModel` (with `RouteState`, `RouteAction`, `RouteEvent`) and `di/RouteModule` are fully covered; everything left is Compose code with 0% covered: `RouteScreen.kt` (278 lines: `RouteRoot`'s event handling and permission flow, both `RouteScreen` overloads, `UserProfileBottomSheet`'s weight input and its parse-and-positive check, `StartTrackingPanel`, `ActivityTypeSelector`, the private `labelFor`/`iconFor` helpers, the previews). The screen holds no JVM-reachable pure logic: `labelFor` and the weight check are inside `@Composable` functions and `iconFor` is private. It needs Robolectric and/or compose-ui-test. The catalog already has `robolectric` (used by `data`), `androidx-compose-ui-test-junit4` and `androidx-compose-ui-test-manifest` (used by `androidApp/app` androidTest), but this module's test source sets don't depend on them yet. The JVM tests of the stale-generation and map-tap fixes (route-generation-stale-in-flight-result, route-map-tap-keeps-generated-route) only dispatch actions back to back; the real UI path is asynchronous and untested.
- Done when: an explicit task adds the existing Robolectric/compose-ui-test catalog entries as this module's test dependencies, `RouteScreen` has tests, Generate followed by Reset or a waypoint change leaves no stale route on screen, a long-press on the map after a route is shown hides the old route and the Start Tracking panel until a new route is generated, and the module's Kover floor is raised in the same PR.
- Refs: `androidApp/feature-route` `RouteScreen`, `RouteRoot`, `UserProfileBottomSheet`, `ActivityTypeSelector`; `androidApp/feature-route/build.gradle.kts` `minBound`; `tm-testing` ("Compose UI tests", "What's actually available today").

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

### drift-protected-path-merge-exception-wording
- Type: drift
- Area: .claude, .github
- Order: 210
- Source: agentic-dev-loop S4b PR review, 2026-10-03
- Problem: `tm-pr-workflow`'s Boundaries say "An agent never merges a PR that touches a protected path. The human merges those." and the header of `.github/CODEOWNERS` says "An agent never merges a PR that touches a path listed here." Decisions 4 and 5 of `docs/epics/agentic-dev-loop.md` make one exception: a subtask PR into an epic branch whose plan `allowed_paths` cover the path (written in `tm-agent-loop`, "Merge conditions", condition 6). S4b's scope did not allow changing either line.
- Done when: both lines state the exception or point to `tm-agent-loop` ("Merge conditions"), in a task that explicitly authorizes the `CODEOWNERS` change.
- Refs: `.claude/skills/tm-pr-workflow/SKILL.md` ("Boundaries"); `.github/CODEOWNERS` (header comment); `.claude/skills/tm-agent-loop/SKILL.md` ("Merge conditions"); `docs/epics/agentic-dev-loop.md` (Decisions 4 and 5).

### drift-plan-decision-8-maps-failure-level-to-changes
- Type: drift
- Area: docs
- Order: 220
- Source: agentic-dev-loop run 7 (PR #93 or the number this PR gets), 2026-10-04
- Problem: Decision 8 of `docs/epics/agentic-dev-loop.md` maps the `Review — pr-reviewer` annotation by level alone ("`failure` = `CHANGES`"). "Map verdict" in `.github/workflows/pr-review.yml` also writes a `failure` annotation when there is no valid report (a failed run, an empty report, a first line that is not a verdict, a wrong `REVIEWED_SHA`), and `tm-agent-loop` section 7 maps by level and the start of the message (`APPROVE.`, `ESCALATE_TO_HUMAN:`, `CHANGES:`), reading anything else as `NOT_APPROVE`. Decision 7 now says a PR whose check never produced a valid report does not count toward the trial, which only the message start tells apart from `CHANGES`.
- Done when: Decision 8 maps by level and the start of the message, as `tm-agent-loop` section 7 does, and says that any other annotation is not a verdict.
- Refs: `docs/epics/agentic-dev-loop.md` (Decisions 7 and 8); `.github/workflows/pr-review.yml` (step "Map verdict"); `.claude/skills/tm-agent-loop/SKILL.md` ("Reading the CI verdict").

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

### drift-robolectric-users-claude-md-readme
- Type: drift
- Area: CLAUDE.md, README.md
- Order: 270
- Source: History and Details Compose UI tests PR (agent loop run 23), 2026-10-05
- Problem: since that PR `feature-history`'s JVM tests use Robolectric (with compose-ui-test) for Compose UI tests of `HistoryScreen` and `DetailsScreen`. `CLAUDE.md` ("Testing stack") still says "Robolectric (catalog entry, used by `data`)", and `README.md` ("Testing strategy") still says "Android-only persistence tests use Robolectric where genuinely needed", with no mention of Compose UI tests. Neither file was in that PR's allowed files.
- Done when: both lines name the Compose UI tests in `feature-history` (and any later feature module) as Robolectric users, or the human decides they stay as they are.
- Refs: `CLAUDE.md` ("Testing stack"); `README.md` ("Testing strategy", the "Testing" row of the stack table); `androidApp/feature-history/build.gradle.kts`; `tm-testing` ("What's actually available today", "Compose UI tests").

### drift-tm-android-tests-section-mockk
- Type: drift
- Area: .claude
- Order: 280
- Source: History and Details Compose UI tests PR (agent loop run 23), 2026-10-05
- Problem: `tm-android`'s "Tests" section says "JUnit4 + MockK for Android-framework tests". MockK is not in `gradle/libs.versions.toml` and no module uses it (`tm-testing`, "What's actually available today"); Android-framework tests use JUnit4, `kotlin.test` assertions and hand-written fakes from `androidApp/core-testing`, under Robolectric where needed.
- Done when: the line describes the current stack (JUnit4, `kotlin.test`, hand-written fakes, Robolectric/compose-ui-test where needed) and points to `tm-testing` for the rest.
- Refs: `.claude/skills/tm-android/SKILL.md` ("Tests"); `.claude/skills/tm-testing/SKILL.md` ("What's actually available today"); `gradle/libs.versions.toml`.

### drift-pr-review-workflow-wrapper-header
- Type: drift
- Area: scripts
- Order: 290
- Source: protected-paths-review S3 (skill rule-change signal PR), 2026-10-06
- Problem: the header comment of `scripts/check-pr-review-workflow.sh` says the self-test "runs the "Run pr-reviewer" and "Map verdict" scripts" and "The scripts under test need jq; without python3 or jq the self-test fails". Since S3 the self-test also runs the "Rule changes from the base" step of `.github/workflows/pr-review.yml` in scratch git repositories (fixtures in `scripts/check-pr-review-workflow-fixtures/rule-changes/`) and also needs `git` and `tar`. The wrapper was not in S3's `allowed_paths`.
- Done when: the header names the three steps and the four tools, as the docstring of `scripts/check-pr-review-workflow.py` and `tm-pr-workflow` ("Tier 1") do.
- Refs: `scripts/check-pr-review-workflow.sh` (header comment); `scripts/check-pr-review-workflow.py` (docstring); `.claude/skills/tm-pr-workflow/SKILL.md` ("Tier 1").

### drift-pr-review-item-5-lowered-minbound
- Type: drift
- Area: .claude
- Order: 300
- Source: protected-paths-review S2 (Kover floors ratchet PR), 2026-10-06
- Problem: `tm-pr-review` checklist item 5 ("Deleted or weakened tests") lists "a lowered Kover `minBound`". Since S2 the floors are not `minBound` literals in the module `build.gradle.kts` files: each module passes its entry of `config/kover-floors.properties` to `minBound`, and `scripts/check-kover-floors.sh` fails the gate and CI when an entry is lower than on the base. A lowered floor now shows up in the diff as a lowered value in that file (or as a changed read in a build file). `tm-pr-review` is a protected process skill outside S2's `allowed_paths`.
- Done when: item 5 names a lowered floor in `config/kover-floors.properties` (and a build file that stops reading it), in place of "a lowered Kover `minBound`".
- Refs: `.claude/skills/tm-pr-review/SKILL.md` (Checklist, item 5); `config/kover-floors.properties`; `scripts/check-kover-floors.sh`.

### drift-epic-orchestration-protected-files-list
- Type: drift
- Area: .claude
- Order: 310
- Source: protected-paths-review S4 (open reference skills PR), 2026-10-06
- Problem: `epic-orchestration` ("allowed_paths conventions for this repo") says `allowed_paths` never overrides "the protected files from `tm-pr-workflow` (docs/architecture, CI, lint config, the gate, the hook, skills, `CLAUDE.md`)". `tm-pr-workflow` keeps no such list (`.github/CODEOWNERS` is the single source of truth), and since S4 the four reference skills (`tm-ios`, `tm-android`, `tm-kmp-shared`, `tm-testing`) are not protected. The same skill ("The plan") also says `docs/epics/` "sits outside the protected `docs/architecture/`", while CODEOWNERS owns `/docs/epics/`. `epic-orchestration` is a protected process skill outside S4's `allowed_paths`.
- Done when: both places point to `.github/CODEOWNERS` (and `scripts/check-protected-paths.sh --files`) for what is protected instead of naming paths, and no longer say that every skill is protected or that `docs/epics/` is unprotected.
- Refs: `.claude/skills/epic-orchestration/SKILL.md` ("allowed_paths conventions for this repo", "The plan"); `.github/CODEOWNERS`; `.claude/skills/tm-pr-workflow/SKILL.md` ("Boundaries").

### drift-loop-skill-reviewdecision-empty-at-zero-approvals
- Type: drift
- Area: .claude
- Order: 910
- Source: agentic-dev-loop S5 test, 2026-10-03
- Problem: `tm-agent-loop` ("Reading the CI verdict") tells the agent to use `reviewDecision` instead of `reviewRequests`. With "Require review from Code Owners" on and required approvals at 0, `reviewDecision` stayed empty on a protected PR both before and after the code owner approved it (PR #85, a closed throwaway); only `mergeStateStatus` (`BLOCKED`, then `CLEAN`), `requested_reviewers` and the reviews list showed the review state.
- Done when: the skill names `mergeStateStatus`, `gh api repos/{owner}/{repo}/pulls/<N>/reviews` and `requested_reviewers` as the signals for a pending or given review, and says that `reviewDecision` is empty at 0 required approvals.
- Refs: `.claude/skills/tm-agent-loop/SKILL.md` ("Reading the CI verdict").

### drift-epic-orchestration-gate-scope-after-light-decision
- Type: drift
- Area: .claude
- Order: 920
- Source: agentic-dev-loop run 1 (PR #87), 2026-10-03
- Problem: `epic-orchestration`'s "Resource contention" bullet says "Every subtask runs the full gate: Gradle `detekt`, `lint`, `allTests test`, the Kover coverage report and `koverVerify`, `assembleDebug`, plus SwiftLint, the XCFramework build and `xcodebuild` once the diff touches `iosApp/` or the shared layer." Since #87 `scripts/pre-push-check.sh` and CI skip those heavy steps when `scripts/classify-changes.sh` decides `light` (non-source changes only), so a subtask with only non-source changes does not run them.
- Done when: the lines say the heavy steps run unless `scripts/classify-changes.sh` decides `light`, and point to that script instead of repeating its allowlist.
- Refs: `.claude/skills/epic-orchestration/SKILL.md` ("Resource contention"); `scripts/classify-changes.sh`; `scripts/pre-push-check.sh`.
