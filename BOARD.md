# Board

The backlog of open epics, tasks and drift, so follow-ups are not lost between PRs. It is
not a plan or a status tracker: if a record exists, the item is open. Records are only added,
deleted, or narrowed when partly done. They never move between sections.

Sections are by type: **Epics** (multi-PR, plan under `docs/epics/`), **Tasks** (one PR),
**Drift** (docs/skills/comments that disagree with the code, found but not fixed). Each
record is a `### <slug>` heading (kebab-case, unique, descriptive, never a counter) followed by
these fields, in order: Type (epic | task | drift), Area, Priority (next | soon | later),
Source, Problem, Done when, Refs. Records are ordered next, soon, later within each section.

Rules for adding and deleting records: the "Board" section of `.claude/skills/tm-pr-workflow/SKILL.md`.

## Epics

### route-completion-to-domain
- Type: epic
- Area: domain, iosApp/Tracking, androidApp/feature-tracking
- Priority: soon
- Source: audit + chat 2026-10-01
- Problem: Route-completion detection is written once per platform: on iOS inside `TrackingView` (`isRouteCompleted`, `routeCompletionIndexMargin`, `routeCompletionThresholdMeters`, its own `routeProgress`/`lastProgressIndex` state), on Android in `feature-tracking`'s `RouteCompletionTracker`. Neither is in `domain`, so the platforms can diverge. `calculateRouteProgress` in domain has no guard for out-of-range input: a `previousIndex` past the last point gives an empty search range and `subList` throws, and a negative `previousIndex` indexes out of bounds.
- Done when: completion logic lives in `domain` with `kotlin.test` coverage, both platforms call it, `TrackingView` only renders, `calculateRouteProgress` handles out-of-range `previousIndex` (and `searchWindow`) without throwing, and a human-approved plan exists under `docs/epics/`.
- Refs: `iosApp/Packages/Tracking/Sources/Tracking/TrackingView.swift` (`isRouteCompleted`, `updateRouteProgress`); `androidApp/feature-tracking` `RouteCompletionTracker`; `domain` `RouteProgress` / `calculateRouteProgress`; `epic-orchestration` skill.

### figma-design-system
- Type: epic
- Area: design
- Priority: later
- Source: chat 2026-10-01
- Problem: There is no design system and there are no screens in Figma. The goal is tokens and screens in Figma that agents read through the Figma MCP to implement UI. This is deliberately the LAST item on the board: start it only after everything else.
- Done when: a token-based design system and the main screens exist in Figma, and an agent can implement a screen from them on both platforms.
- Refs: `androidApp/core-ui`, `iosApp/Packages/DesignSystem`; Figma MCP.

## Tasks

### ios-history-details-delete-and-load-errors
- Type: task
- Area: iosApp/History, data
- Priority: soon
- Source: bugfix/ios-double-tap-and-stale-route-results PR (History/Details half of the former `ios-double-tap-and-stale-route-results`)
- Problem: `DetailsViewModel.onDeleteConfirmed` deletes and calls `onDeleted` on every call, so a repeated delete confirmation deletes twice and calls `onDeleted` twice; it also ignores a failed delete (`try?`) and still calls `onDeleted`. `DetailsViewModel`'s load (`getActivity`) and `HistoryViewModel.deleteActivity` call the repository with `try?`, so a failed load shows nothing and a failed delete is never reported. `HistoryViewModel.observe` iterates `observeActivities()`; SKIE's `SkieSwiftFlowIterator.next()` calls `fatalError` on any non-cancellation error, so a failure in the Room-backed Flow (`ActivityHistoryRepositoryImpl.observeActivities`, no `catch`) terminates the app. `@Throws` does not apply to a `Flow`. Found by reading the code; not reproduced on a device and not pinned by tests. Design notes: History and Details have no error channel today, so the fix needs a published error state shown by an alert in the views (same "Something went wrong. Please try again." wording as Route and Tracking); a Flow failure must be handled on the Kotlin side before SKIE's iterator, which also changes Android's `HistoryViewModel` (spinner instead of crash), so coordinate with `android-persistence-errors-unhandled`; best-effort side effects that may stay silent (`deleteSnapshotFile`, Live Activity `Activity.request`) need a comment saying why, and a short exception in the `tm-ios` "never drop an error" rule.
- Done when: on iOS a repeated delete confirmation deletes once and calls `onDeleted` once, with a test (as Android's `DetailsViewModel` does). No `try?` is left in `DetailsViewModel`/`HistoryViewModel`: a failed load or delete reaches the user per the `@Throws` policy in `tm-kmp-shared` (a failed delete does not call `onDeleted`), and a failure in `observeActivities()` can no longer reach Swift unhandled (handled on the Kotlin side before SKIE's iterator), each with a test.
- Refs: iOS `DetailsViewModel.onDeleteConfirmed`, `DetailsViewModel` load, `HistoryViewModel.observe`, `deleteActivity`; Android `DetailsViewModel.deleteActivity`; `data` `ActivityHistoryRepositoryImpl.observeActivities`; SKIE `SkieSwiftFlowIterator`; `tm-kmp-shared` ("`@Throws` policy"); `tm-ios` ("SKIE interop from Swift": the "never drop an error" rule, whose "Known remaining `try?` sites" line still names the removed slug `ios-double-tap-and-stale-route-results`); `deleteSnapshotFile`, `TrackingLiveActivityController` (`Activity.request`); board `android-persistence-errors-unhandled`.

### android-persistence-errors-unhandled
- Type: task
- Area: androidApp
- Priority: soon
- Source: bugfix/ios-swallowed-errors-and-throws-policy PR
- Problem: The Android ViewModels call the persistence repositories inside `viewModelScope.launch` without handling a failure, and no `CoroutineExceptionHandler` exists, so a database or storage exception crashes the app. `RouteViewModel` `saveUserProfile`, `startTracking` and `getAndUpdateUserProfile` call `UserProfileRepository` unguarded; `TrackingViewModel`'s init profile load is unguarded, and `finish` resets `isSessionSaved` on failure but rethrows with `getOrThrow()`; `DetailsViewModel`'s init `getActivity` is unguarded and `deleteActivity` rethrows the same way; `HistoryViewModel.deleteActivity` is unguarded and its `state` (`observeActivities().stateIn`) has no `catch`. Found by reading the code; not reproduced. `HistoryViewModel.state` can build on the domain `ObserveActivitiesUseCase` (added by bugfix/ios-history-details-delete-and-load-errors, which iOS already uses) to survive a failing `observeActivities()`.
- Done when: the `@Throws` policy's rules 4 and 5 in `tm-kmp-shared` hold on Android too: every such failure reaches the user through the screen's existing error event or state, never crashes, and leaves state consistent (a failed save does not update the profile, a failed start does not navigate, a failed delete does not send `Deleted`), each with an `onAction` test using a throwing fake from `core-testing`.
- Refs: `androidApp/feature-route` `RouteViewModel`; `feature-tracking` `TrackingViewModel` (init, `finish`); `feature-history` `DetailsViewModel` (init, `deleteActivity`), `HistoryViewModel` (`state`, `deleteActivity`); `core-testing` `FakeUserProfileRepository`, `FakeActivityHistoryRepository`; `tm-kmp-shared` ("`@Throws` policy").

### ios-init-time-error-events-dropped
- Type: task
- Area: iosApp/Route, iosApp/Tracking
- Priority: later
- Source: bugfix/ios-swallowed-errors-and-throws-policy PR review
- Problem: In iOS `RouteViewModel` and `TrackingViewModel`, `emit(_:)` yields to `eventsContinuation`, which exists only once the View's `.task` has called `makeEventsStream()`. The loads `RouteViewModel.getAndUpdateUserProfile`, `loadCurrentLocation` and `TrackingViewModel.loadUserProfile` start in `init`, before the View consumes events. If one fails before the stream exists, its `.showError` is yielded to a nil continuation and silently lost. The same happens while a pushed screen covers `RouteView`: its `.task` is cancelled and only re-created on return, so an event emitted in between is lost. The existing `loadCurrentLocation` error has the same timing. The new tests pass only because they create the recorder right after building the ViewModel, before the failing load completes. So the `@Throws` policy rule "Swift never drops an error" does not yet hold for init-time loads. Found by reading the code; not reproduced on a device. On the simulator a failure injected in `UserProfileRepositoryImpl.getUserProfile` was shown when the app opened (human check on PR #76), so the loss is timing dependent; the covered-screen case remains untested.
- Done when: an error produced before the View starts consuming `makeEventsStream()`, or while no consumer is active, is delivered to the next consumer instead of being lost (for example by holding pending events until a stream exists), in both ViewModels, with a test per ViewModel that fails the profile (or location) load before calling `makeEventsStream()` and still receives the error.
- Refs: `RouteViewModel.emit`, `makeEventsStream`, `getAndUpdateUserProfile`, `loadCurrentLocation`; `TrackingViewModel.emit`, `makeEventsStream`, `loadUserProfile`; `RouteView`/`TrackingView` `.task`; `tm-kmp-shared` ("`@Throws` policy" rule 4).

### ios-live-activity-ticker
- Type: task
- Area: iosApp/Tracking
- Priority: later
- Source: PR #66 review
- Problem: The Live Activity's elapsed time is a static `elapsedMillis` value. It changes only when a tracking-state emission (driven by location events) reaches `TrackingLiveActivityController.update`, which is also throttled to one update per second. Without location events it freezes, then jumps.
- Done when: the elapsed time uses a system timer anchored to a start date and advances without updates (metrics may still depend on updates). Verified on a real device; the simulator does not suspend like a device.
- Refs: `TrackingLiveActivityController.update` / `minimumUpdateInterval`; `TrackingActivityAttributes.ContentState.elapsedMillis`; `iosApp/TrackingWidget/TrackingLiveActivity.swift` `formatElapsed`.

### tracking-ui-timer-independent-of-location
- Type: task
- Area: domain, iosApp, androidApp
- Priority: later
- Source: PR #66 test
- Problem: The in-app elapsed time shows `metrics.elapsedMillis` from the tracking state, which is only re-emitted on location events. There is no ticker, so a stationary device freezes the timer and the display can jump (observed by 2 s).
- Done when: the displayed time ticks independently of location events on both platforms, without changing the domain's accounting of elapsed time.
- Refs: `TrackingSessionManager` (state emissions); Android `TrackingScreen` (`formatElapsedTime(metrics.elapsedMillis)`); iOS `MetricsDisplay`.

### android-tracking-notification-content
- Type: task
- Area: data
- Priority: later
- Source: PR #66 test
- Problem: The Android foreground tracking notification (built in `data`'s androidMain `TrackingService.buildNotification`) shows only "Tracking..."/"Paused - " plus distance. It has no elapsed time or other metrics. No doc or skill records whether that is intentional.
- Done when: it shows elapsed time and key metrics, or the decision not to is documented.
- Refs: `data/src/androidMain` `TrackingService.buildNotification`.

### tracking-location-path-double-clock-read
- Type: task
- Area: domain
- Priority: later
- Source: PR #66 drift
- Problem: In `TrackingSessionManager.observeLocation`, each `LocationUpdate.Success` reads `clock.elapsedRealtimeMillis()` twice: once for `speedCalculator.calculate` and once for `TrackingEvent.LocationReceived`. Speed and accounting can therefore see slightly different timestamps for the same event.
- Done when: the clock is read once per event and reused, with a test.
- Refs: `domain` `TrackingSessionManager.observeLocation`, `SpeedCalculator`.

### polyline-decoder-invalid-characters
- Type: task
- Area: data
- Priority: later
- Source: PR #68 review
- Problem: `decodePolyline` rejects only truncated input. Characters outside the valid encoded-polyline range (`?`..`~`) are not rejected: `code - 63` is used as-is and silently decodes to garbage coordinates instead of failing.
- Done when: invalid characters throw `IllegalArgumentException` (which `DirectionsRepositoryImpl` already maps to `DirectionsApiError`), with tests.
- Refs: `data` `decodePolyline` / `decodeValue`; `PolylineDecoderTest`; `DirectionsRepositoryImpl.getClosedRoute`.

### ci-use-build-kmp-framework-script
- Type: task
- Area: ci
- Priority: later
- Source: PR #67 drift
- Problem: CI's `ios` job builds the shared XCFramework by calling `./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework` directly instead of `scripts/build-kmp-framework.sh`, so CI never exercises the script the gate and the Xcode pre-action use.
- Done when: CI uses the script. The task must explicitly authorize the CI config change.
- Refs: `.github/workflows/ci.yml` (ios job); `scripts/build-kmp-framework.sh`.

### gate-ios-steps-miss-root-gradle-changes
- Type: task
- Area: scripts
- Priority: later
- Source: PR #67 drift + PR #75 review
- Problem: `scripts/pre-push-check.sh` runs its iOS steps only when the branch diff matches `^(iosApp/|domain/|data/|core/|shared/)`. Root Gradle files (`build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`) and `gradle/libs.versions.toml` also change the framework, but they skip the iOS steps. The pattern is also too broad in the other direction: every file under `iosApp/`, `domain/`, `data/`, `core/` and `shared/` sets `TOUCHES_IOS_OR_SHARED`, including documentation such as `data/README.md`, so a documentation-only change runs the full iOS build and SwiftLint (observed in #75).
- Done when: documentation files (`*.md`) under those folders don't trigger the iOS steps; a change to a Kotlin or Swift source or build file under those folders still does; and the root Gradle files (`build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`) and `gradle/libs.versions.toml` also trigger them.
- Refs: `scripts/pre-push-check.sh` (`TOUCHES_IOS_OR_SHARED`).

### kover-verify-remaining-modules
- Type: task
- Area: build
- Priority: later
- Source: original coverage plan
- Problem: `koverVerify` floors exist only in `domain`, `data` and the three `androidApp/feature-*` modules. `core`, `shared`, `androidApp/app` and `androidApp/core-ui` have none. The repo has no record that the merged root report was re-checked against the per-module reports (`data` excludes generated classes only in its own report).
- Done when: each of those modules has a floor or an explicit documented exclusion, and the root-vs-module report check is written down.
- Refs: `build.gradle.kts` (root Kover merge); each module's `build.gradle.kts` `kover` block; `tm-pr-workflow` ("Tier 1").

### document-ios-start-after-stop-limitation
- Type: task
- Area: docs, iosApp
- Priority: later
- Source: audit + chat 2026-10-01
- Problem: iOS `TrackingViewModel.onStopClicked` cancels and clears `stateObservationTask` and `locationIssuesObservationTask`, which are only started from `init`. A second `onStartClicked` on the same instance would therefore not observe state. Users can't hit this today, because every Stop path leaves the screen first: in-app Stop (controls row and exit alert) calls `dismiss()`, Live Activity Stop (`handleStopNotification`) emits `.dismissed`, and auto-completion shows `finishCard` instead of the controls. Document it as a known limitation; don't fix it.
- Done when: documented in `tm-ios` or `LEARNINGS.md`.
- Refs: iOS `TrackingViewModel.onStopClicked`, `onStartClicked`, `observeTrackingState`, `handleStopNotification`; `TrackingView` (`controlsRow`, `finishCard`, `.dismissed` handling).

### directions-http-status-ignored
- Type: task
- Area: data
- Priority: later
- Source: PR #70
- Problem: `networkModule`'s `HttpClient` doesn't set `expectSuccess`, and neither `safeApiCall` nor `DirectionsRepositoryImpl.getClosedRoute` checks the HTTP status. A 4xx/5xx response whose body is a valid `DirectionsResponseDto` with status "OK" returns a successful route. A non-2xx response with a non-JSON body fails only through deserialization, so the HTTP status never reaches the `DirectionsApiError` cause. Pinned by `DirectionsRepositoryImplTest` "HTTP error status with a valid OK body currently returns a successful route".
- Done when: a non-2xx Directions response returns `RouteError.DirectionsApiError` whose cause names the HTTP status, and that pinned test is changed to assert it.
- Refs: `data` `di/NetworkModule.kt`, `common/SafeApiCall.kt`, `DirectionsRepositoryImpl.getClosedRoute`; `DirectionsRepositoryImplTest`.

### test-data-remaining-untested-classes
- Type: task
- Area: data
- Priority: later
- Source: PR #70
- Problem: After the directions tests, `data` is at 44.38% line coverage (142/320, Android host Kover report, generated code excluded). The five biggest gaps (uncovered lines, nested/lambda classes merged into their source class) all have 0% covered: `AndroidLocationRepositoryImpl` (49), `TrackingService` (44), `di/CommonTrackingModule` (14), `di/NetworkModule` (10), `di/UseCaseModule` (10). iOS-only code (`IosLocationRepositoryImpl`, `IosTrackingServiceLauncher`) isn't in the report at all, because Kover can't measure the iOS run.
- Done when: those classes have tests (or a documented reason why one can't be tested on the host), and the `data` Kover floor is raised in the same PR.
- Refs: `data` `location/AndroidLocationRepositoryImpl`, `tracking/TrackingService`, `di/CommonTrackingModule`, `di/NetworkModule`, `di/UseCaseModule`; `data/build.gradle.kts` `kover.reports.verify`; `tm-testing`.

### test-feature-tracking-compose-ui
- Type: task
- Area: androidApp/feature-tracking
- Priority: later
- Source: test-feature-tracking PR
- Problem: After the JVM tests, `feature-tracking`'s `TrackingViewModel`, `RouteCompletionTracker` and `di/TrackingUiModule` are fully covered; everything left is Android-framework code with 0% covered: `TrackingScreen` (284 lines: `TrackingRoot`'s event handling and permission flow, both `TrackingScreen` overloads, `MetricsDisplay`, the preview, `hasLocationPermission`) and `util/MapSnapshotSaver` (19 lines: `saveSnapshotToFile` scaling, PNG write and `IOException` path). They need Robolectric and/or compose-ui-test. The catalog already has `robolectric` (used by `data`), `androidx-compose-ui-test-junit4` and `androidx-compose-ui-test-manifest` (used by `androidApp/app` androidTest), but this module's test source sets don't depend on them yet. The JVM tests of the double-Finish fix (tracking-finish-saves-twice) can only dispatch two `Finish` actions back to back; the real UI path is asynchronous and untested.
- Done when: an explicit task adds the existing Robolectric/compose-ui-test catalog entries as this module's test dependencies, `TrackingScreen` and `saveSnapshotToFile` have tests, a double tap on the Finish button, including the asynchronous `map.snapshot` callback path in `TrackingScreen`, results in exactly one saved activity and one `Saved`, and the module's Kover floor is raised in the same PR.
- Refs: `androidApp/feature-tracking` `TrackingScreen`, `MetricsDisplay`, `util/MapSnapshotSaver.kt`; `androidApp/feature-tracking/build.gradle.kts` `minBound`; `tm-testing` ("Compose UI tests", "What's actually available today").

### test-feature-history-compose-ui
- Type: task
- Area: androidApp/feature-history
- Priority: later
- Source: test-feature-history PR
- Problem: After the JVM tests, `feature-history`'s `HistoryViewModel`, `DetailsViewModel`, `util/SnapshotFileDeleter` and `di/HistoryUiModule` are fully covered; everything left is Compose code with 0% covered: `HistoryScreen` (196 lines: `HistoryRoot`'s event handling, both `HistoryScreen` overloads, `ActivityRow`, the private `iconFor`/`labelFor` helpers, the preview) and `DetailsScreen` (179 lines: `DetailsRoot`'s event handling, both `DetailsScreen` overloads, the delete `AlertDialog`, `ActivityDetailsContent`, the preview). The screens hold no JVM-reachable pure logic: `labelFor` is `@Composable` and `iconFor` is private. They need Robolectric and/or compose-ui-test. The catalog already has `robolectric` (used by `data`), `androidx-compose-ui-test-junit4` and `androidx-compose-ui-test-manifest` (used by `androidApp/app` androidTest), but this module's test source sets don't depend on them yet. The JVM tests of the double-delete fix (details-delete-confirmed-twice) can only dispatch two `DeleteConfirmed` actions back to back; the real UI path is asynchronous and untested.
- Done when: an explicit task adds the existing Robolectric/compose-ui-test catalog entries as this module's test dependencies, `HistoryScreen` and `DetailsScreen` have tests, a double tap on the delete dialog's confirm button in `DetailsScreen` results in exactly one delete and one `Deleted` (History is still on screen afterwards), and the module's Kover floor is raised in the same PR.
- Refs: `androidApp/feature-history` `HistoryScreen`, `DetailsScreen`; `androidApp/feature-history/build.gradle.kts` `minBound`; `tm-testing` ("Compose UI tests", "What's actually available today").

### test-feature-route-compose-ui
- Type: task
- Area: androidApp/feature-route
- Priority: later
- Source: test-feature-route PR
- Problem: After the JVM tests, `feature-route`'s `RouteViewModel` (with `RouteState`, `RouteAction`, `RouteEvent`) and `di/RouteModule` are fully covered; everything left is Compose code with 0% covered: `RouteScreen.kt` (278 lines: `RouteRoot`'s event handling and permission flow, both `RouteScreen` overloads, `UserProfileBottomSheet`'s weight input and its parse-and-positive check, `StartTrackingPanel`, `ActivityTypeSelector`, the private `labelFor`/`iconFor` helpers, the previews). The screen holds no JVM-reachable pure logic: `labelFor` and the weight check are inside `@Composable` functions and `iconFor` is private. It needs Robolectric and/or compose-ui-test. The catalog already has `robolectric` (used by `data`), `androidx-compose-ui-test-junit4` and `androidx-compose-ui-test-manifest` (used by `androidApp/app` androidTest), but this module's test source sets don't depend on them yet. The JVM tests of the stale-generation and map-tap fixes (route-generation-stale-in-flight-result, route-map-tap-keeps-generated-route) only dispatch actions back to back; the real UI path is asynchronous and untested.
- Done when: an explicit task adds the existing Robolectric/compose-ui-test catalog entries as this module's test dependencies, `RouteScreen` has tests, Generate followed by Reset or a waypoint change leaves no stale route on screen, a long-press on the map after a route is shown hides the old route and the Start Tracking panel until a new route is generated, and the module's Kover floor is raised in the same PR.
- Refs: `androidApp/feature-route` `RouteScreen`, `RouteRoot`, `UserProfileBottomSheet`, `ActivityTypeSelector`; `androidApp/feature-route/build.gradle.kts` `minBound`; `tm-testing` ("Compose UI tests", "What's actually available today").

### test-ios-ui-double-tap-and-stale-results
- Type: task
- Area: iosApp
- Priority: later
- Source: bugfix/ios-history-details-delete-and-load-errors PR
- Problem: The iOS ViewModel guards for a repeated Finish (`TrackingViewModel.onFinishClicked`), a repeated delete confirmation (`DetailsViewModel.onDeleteConfirmed`), a repeated Generate (`RouteViewModel.onGenerateRouteClicked`) and Generate followed by Reset (`onResetClicked`) are covered by Swift unit tests in the packages, but nothing proves the Views deliver such taps to the ViewModel the way the tests do, and they can't be checked reliably by hand. The Android equivalents are the three `test-feature-*-compose-ui` records. There is no iOS UI-test target today: `TrailMetrics.xcodeproj` has only the `TrailMetrics` app and the `TrackingWidget` extension, and the shared `TrailMetrics` scheme has no testables. Design note: XCUITest drives the real app, so it needs deterministic fakes (location, directions, storage) injected at app launch (a launch argument read by the composition root, or a Koin override in `doInitKoinIos`); that seam doesn't exist yet and is part of this task.
- Done when: a UI-test target exists in the shared scheme with a launch-time fake seam, and XCUITest scenarios cover: Finish tapped twice (one History entry), Generate then Reset (no route afterwards), Generate tapped twice (one directions request), delete confirmation tapped twice (one deletion), and a failed delete showing the "Error" alert.
- Refs: `iosApp/TrailMetrics.xcodeproj`; `TrailMetricsApp` (`doInitKoinIos`), `KoinHelper`; `TrackingView`/`TrackingViewModel.onFinishClicked`; `RouteView`/`RouteViewModel.onGenerateRouteClicked`, `onResetClicked`; `DetailsView`/`DetailsViewModel.onDeleteConfirmed`; `HistoryView`; board `test-feature-tracking-compose-ui`, `test-feature-history-compose-ui`, `test-feature-route-compose-ui`.

## Drift

### drift-suppress-comments
- Type: drift
- Area: androidApp, data
- Priority: later
- Source: chat 2026-10-01
- Problem: Several suppressions have no reason next to them: `@Suppress("LocalContextGetResourceValueCall")` on the events `LaunchedEffect` in `TrackingScreen` and `RouteScreen`; `@Suppress("UnusedPrivateMember")` on `RouteScreen`'s `ActivityTypeSelectorPreview` (its siblings have the preview comment); `@Suppress("TooGenericExceptionCaught")` on `safeApiCall` and twice in `AndroidLocationRepositoryImpl`. Every iOS `swiftlint:disable` has a reason. Whether any existing reason is stale was not checked.
- Done when: every suppression has an accurate reason, or is removed.
- Refs: `TrackingScreen`, `RouteScreen` (feature-tracking, feature-route); `data` `safeApiCall`, `AndroidLocationRepositoryImpl`.
