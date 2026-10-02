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

### throws-policy-and-swallowed-errors
- Type: task
- Area: iosApp, domain
- Priority: soon
- Source: chat 2026-10-01
- Problem: No Kotlin→Swift `@Throws` policy is written down, and usage is inconsistent: `GenerateClosedRouteUseCase` and `GetCurrentLocationUseCase` declare only `RouteError` and `CancellationException`, so any other exception crashes iOS, while `SaveActivityUseCase` declares `Throwable`. Four unstructured throwing `Task { }` blocks silently drop errors: three in iOS `RouteViewModel` (`saveUserProfile`, `onStartTrackingClicked`, `getAndUpdateUserProfile`) and one in `TrackingViewModel` (`loadUserProfile`). Xcode reports these as "Unstructured throwing task is not used" (the call sites were checked in code; the warning was not reproduced in this PR).
- Done when: the policy is written in `tm-kmp-shared`, the four warnings are gone, and errors reach the user or the logs on purpose.
- Refs: `domain` `GenerateClosedRouteUseCase`, `GetCurrentLocationUseCase`, `SaveActivityUseCase`; `iosApp/Packages/Route` `RouteViewModel`; `iosApp/Packages/Tracking` `TrackingViewModel.loadUserProfile`.

### skill-rules-red-test-and-ratchet
- Type: task
- Area: docs
- Priority: soon
- Source: chat 2026-10-01
- Problem: Two working rules are not in the skills. (1) A bugfix starts with a failing (red) test in its own commit. `tm-testing` only has test-first for MVI migrations. (2) The coverage ratchet: raise the Kover floor in the same PR as the tests, set it to measured minus 1-2 points, and verify it by setting it 1 point above measured once to see `koverVerify` fail. `tm-pr-workflow` only says floors sit "a little below" measured coverage.
- Done when: both rules are in `tm-pr-workflow` and/or `tm-testing`.
- Refs: `tm-testing` ("Testing MVI ViewModels", "What to test, and coverage priorities"); `tm-pr-workflow` ("Tier 1").

### ios-double-tap-and-stale-route-results
- Type: task
- Area: iosApp/Tracking, iosApp/History, iosApp/Route
- Priority: soon
- Source: bugfix/double-tap-and-stale-route-results PR
- Problem: The iOS ViewModels have the four defects that PR fixed on Android. `TrackingViewModel.onFinishClicked` saves on every call while the state is finished, so a repeated Finish saves twice and calls `onSaved` twice. `DetailsViewModel.onDeleteConfirmed` deletes and calls `onDeleted` on every call; it also ignores a failed delete (`try?`) and still calls `onDeleted`. `RouteViewModel.onGenerateRouteClicked` starts an untracked `Task`: `onResetClicked` and `onWaypointRemoved` don't cancel it, so a stale route lands afterwards, and reset turns `isLoading` off while it runs, so Generate can call directions again. `onMapTapped` keeps `generatedRoute`, while `onWaypointRemoved` clears it. Found by reading the code; not reproduced on a device and not pinned by tests.
- Done when: on iOS a repeated Finish saves once, a repeated delete confirmation deletes once and calls `onDeleted` once, reset and any waypoint change cancel an in-flight generation, a click while one runs is ignored, and adding a waypoint clears the generated route, each with a test (as Android's `TrackingViewModel`, `DetailsViewModel` and `RouteViewModel` do).
- Refs: iOS `TrackingViewModel.onFinishClicked`, `DetailsViewModel.onDeleteConfirmed`, `RouteViewModel.onGenerateRouteClicked`, `onResetClicked`, `onWaypointRemoved`, `onMapTapped`; Android `TrackingViewModel.finish`, `DetailsViewModel.deleteActivity`, `RouteViewModel.generateRoute`, `addWaypoint`.

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
- Source: PR #67 drift
- Problem: `scripts/pre-push-check.sh` runs its iOS steps only when the branch diff matches `^(iosApp/|domain/|data/|core/|shared/)`. Root Gradle files (`build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`) and `gradle/libs.versions.toml` also change the framework, but they skip the iOS steps.
- Done when: those paths also trigger the iOS steps.
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
- Problem: After the JVM tests, `feature-tracking` is at 30.02% line coverage (130/433). `TrackingViewModel`, `RouteCompletionTracker` and `di/TrackingUiModule` are fully covered; everything left is Android-framework code with 0% covered: `TrackingScreen` (284 lines: `TrackingRoot`'s event handling and permission flow, both `TrackingScreen` overloads, `MetricsDisplay`, the preview, `hasLocationPermission`) and `util/MapSnapshotSaver` (19 lines: `saveSnapshotToFile` scaling, PNG write and `IOException` path). They need Robolectric and/or compose-ui-test. The catalog already has `robolectric` (used by `data`), `androidx-compose-ui-test-junit4` and `androidx-compose-ui-test-manifest` (used by `androidApp/app` androidTest), but this module's test source sets don't depend on them yet. The JVM tests of the double-Finish fix (tracking-finish-saves-twice) can only dispatch two `Finish` actions back to back; the real UI path is asynchronous and untested.
- Done when: an explicit task adds the existing Robolectric/compose-ui-test catalog entries as this module's test dependencies, `TrackingScreen` and `saveSnapshotToFile` have tests, a double tap on the Finish button, including the asynchronous `map.snapshot` callback path in `TrackingScreen`, results in exactly one saved activity and one `Saved`, and the module's Kover floor is raised in the same PR.
- Refs: `androidApp/feature-tracking` `TrackingScreen`, `MetricsDisplay`, `util/MapSnapshotSaver.kt`; `androidApp/feature-tracking/build.gradle.kts` `minBound`; `tm-testing` ("Compose UI tests", "What's actually available today").

### test-feature-history-compose-ui
- Type: task
- Area: androidApp/feature-history
- Priority: later
- Source: test-feature-history PR
- Problem: After the JVM tests, `feature-history` is at 12.99% line coverage (56/431). `HistoryViewModel`, `DetailsViewModel`, `util/SnapshotFileDeleter` and `di/HistoryUiModule` are fully covered; everything left is Compose code with 0% covered: `HistoryScreen` (196 lines: `HistoryRoot`'s event handling, both `HistoryScreen` overloads, `ActivityRow`, the private `iconFor`/`labelFor` helpers, the preview) and `DetailsScreen` (179 lines: `DetailsRoot`'s event handling, both `DetailsScreen` overloads, the delete `AlertDialog`, `ActivityDetailsContent`, the preview). The screens hold no JVM-reachable pure logic: `labelFor` is `@Composable` and `iconFor` is private. They need Robolectric and/or compose-ui-test. The catalog already has `robolectric` (used by `data`), `androidx-compose-ui-test-junit4` and `androidx-compose-ui-test-manifest` (used by `androidApp/app` androidTest), but this module's test source sets don't depend on them yet. The JVM tests of the double-delete fix (details-delete-confirmed-twice) can only dispatch two `DeleteConfirmed` actions back to back; the real UI path is asynchronous and untested.
- Done when: an explicit task adds the existing Robolectric/compose-ui-test catalog entries as this module's test dependencies, `HistoryScreen` and `DetailsScreen` have tests, a double tap on the delete dialog's confirm button in `DetailsScreen` results in exactly one delete and one `Deleted` (History is still on screen afterwards), and the module's Kover floor is raised in the same PR.
- Refs: `androidApp/feature-history` `HistoryScreen`, `DetailsScreen`; `androidApp/feature-history/build.gradle.kts` `minBound`; `tm-testing` ("Compose UI tests", "What's actually available today").

### test-feature-route-compose-ui
- Type: task
- Area: androidApp/feature-route
- Priority: later
- Source: test-feature-route PR
- Problem: After the JVM tests, `feature-route` is at 25.87% line coverage (97/375). `RouteViewModel` (with `RouteState`, `RouteAction`, `RouteEvent`) and `di/RouteModule` are fully covered; everything left is Compose code with 0% covered: `RouteScreen.kt` (278 lines: `RouteRoot`'s event handling and permission flow, both `RouteScreen` overloads, `UserProfileBottomSheet`'s weight input and its parse-and-positive check, `StartTrackingPanel`, `ActivityTypeSelector`, the private `labelFor`/`iconFor` helpers, the previews). The screen holds no JVM-reachable pure logic: `labelFor` and the weight check are inside `@Composable` functions and `iconFor` is private. It needs Robolectric and/or compose-ui-test. The catalog already has `robolectric` (used by `data`), `androidx-compose-ui-test-junit4` and `androidx-compose-ui-test-manifest` (used by `androidApp/app` androidTest), but this module's test source sets don't depend on them yet. The JVM tests of the stale-generation and map-tap fixes (route-generation-stale-in-flight-result, route-map-tap-keeps-generated-route) only dispatch actions back to back; the real UI path is asynchronous and untested.
- Done when: an explicit task adds the existing Robolectric/compose-ui-test catalog entries as this module's test dependencies, `RouteScreen` has tests, Generate followed by Reset or a waypoint change leaves no stale route on screen, a long-press on the map after a route is shown hides the old route and the Start Tracking panel until a new route is generated, and the module's Kover floor is raised in the same PR.
- Refs: `androidApp/feature-route` `RouteScreen`, `RouteRoot`, `UserProfileBottomSheet`, `ActivityTypeSelector`; `androidApp/feature-route/build.gradle.kts` `minBound`; `tm-testing` ("Compose UI tests", "What's actually available today").

## Drift

### drift-mvi-epic-approval-placeholder
- Type: drift
- Area: docs
- Priority: soon
- Source: chat 2026-10-01
- Problem: `docs/epics/mvi-presentation-migration.md` still has the template placeholder "Approved by: <human> on <YYYY-MM-DD>".
- Done when: it holds the real approver and date (the human must supply them), or the line is removed.
- Refs: `docs/epics/mvi-presentation-migration.md` header.

### drift-claude-md-testing-stack
- Type: drift
- Area: docs
- Priority: soon
- Source: PR #68 drift
- Problem: CLAUDE.md "Testing stack (fixed, do not introduce alternatives)" lists MockK, which is not in `gradle/libs.versions.toml`. It still carries the Truth-migration text, though no `com.google.truth` import remains, and it doesn't mention Ktor `MockEngine` (`ktor-client-mock`), which the HTTP tests use.
- Done when: the section matches reality. The task must authorize editing CLAUDE.md.
- Refs: `CLAUDE.md` "Testing stack"; `gradle/libs.versions.toml`; `tm-testing` description.

### drift-readme-stack-row
- Type: drift
- Area: docs
- Priority: soon
- Source: PR #68 drift
- Problem: The Testing row of README.md's stack table lists "JUnit4 + Google Truth + MockK + Robolectric" for Android. Neither Truth nor MockK is in the catalog.
- Done when: the row matches the real catalog.
- Refs: `README.md` stack table (Testing row); `gradle/libs.versions.toml`.

### drift-data-readme-api-vs-implementation
- Type: drift
- Area: docs
- Priority: soon
- Source: PR #68 drift
- Problem: `data/README.md` says `data` depends on `domain` "as `api`, so `shared` can re-export it", but `data/build.gradle.kts` declares `implementation(project(":domain"))`.
- Done when: the README matches the build file.
- Refs: `data/README.md` (dependencies paragraph); `data/build.gradle.kts` dependencies.

### drift-tm-testing-gradle-test-counts
- Type: drift
- Area: docs
- Priority: soon
- Source: PR #68 drift
- Problem: `tm-testing`'s "Detekt / CI note" says `./gradlew test` must show the same test count before and after a test-framework or dependency change. That task runs zero KMP tests; the gate uses `allTests test`.
- Done when: the note uses the real counting method.
- Refs: `.claude/skills/tm-testing/SKILL.md` "Detekt / CI note"; `scripts/pre-push-check.sh`.

### drift-overview-ios-build-integration
- Type: drift
- Area: docs/architecture
- Priority: soon
- Source: PR #67 drift
- Problem: `docs/architecture/OVERVIEW.md` "iOS build integration" still describes a Run Script phase that hashes `.kt`/`.kts` files and re-runs Gradle when the hash changes. It doesn't describe the current flow: a shared-scheme Build pre-action running `scripts/build-kmp-framework.sh`, with the phase kept as a safety net.
- Done when: the section is updated. The task must explicitly authorize editing `docs/architecture`.
- Refs: `docs/architecture/OVERVIEW.md` "iOS build integration"; `scripts/build-kmp-framework.sh`; `tm-ios` "Build integration".

### drift-suppress-comments
- Type: drift
- Area: androidApp, data
- Priority: later
- Source: chat 2026-10-01
- Problem: Several suppressions have no reason next to them: `@Suppress("LocalContextGetResourceValueCall")` on the events `LaunchedEffect` in `TrackingScreen` and `RouteScreen`; `@Suppress("UnusedPrivateMember")` on `RouteScreen`'s `ActivityTypeSelectorPreview` (its siblings have the preview comment); `@Suppress("TooGenericExceptionCaught")` on `safeApiCall` and twice in `AndroidLocationRepositoryImpl`. Every iOS `swiftlint:disable` has a reason. Whether any existing reason is stale was not checked.
- Done when: every suppression has an accurate reason, or is removed.
- Refs: `TrackingScreen`, `RouteScreen` (feature-tracking, feature-route); `data` `safeApiCall`, `AndroidLocationRepositoryImpl`.

### drift-test-count-method
- Type: drift
- Area: docs
- Priority: later
- Source: PR #66/#68 reviews
- Problem: Kotlin test totals in successive PRs don't line up because each PR counted a different scope: #65 reported 236 after, #66 231 before / 243 after, #68 257 before. `tm-pr-workflow` says to read counts from `allTests` JUnit XML but defines no scope.
- Done when: `tm-pr-workflow` defines one counting method (per module, per target), and PR reports use it.
- Refs: `tm-pr-workflow` "PR description" (Tier 1 item); PRs #65, #66, #68.
