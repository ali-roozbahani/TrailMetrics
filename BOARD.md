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

### test-feature-tracking
- Type: task
- Area: androidApp/feature-tracking
- Priority: soon
- Source: chat 2026-10-01
- Problem: Coverage is low. The module has `TrackingViewModelTest` and `RouteCompletionTrackerTest`, but its Kover floor is only `minBound(25)`, and the rest of its logic (state mapping, calorie recompute, location-issue handling) is thinly tested.
- Done when: real tests for its ViewModel/UI logic land, and the module's Kover floor is raised in the same PR. One PR for this module only.
- Refs: `androidApp/feature-tracking` `TrackingViewModel`, `TrackingScreen`; `androidApp/feature-tracking/build.gradle.kts` `minBound`; `tm-testing`.

### test-feature-history
- Type: task
- Area: androidApp/feature-history
- Priority: soon
- Source: chat 2026-10-01
- Problem: Coverage is low. The module has `HistoryViewModelTest` and `DetailsViewModelTest`, but its Kover floor is only `minBound(10)`.
- Done when: real tests for its ViewModel/UI logic land, and the module's Kover floor is raised in the same PR. One PR for this module only.
- Refs: `androidApp/feature-history` `HistoryViewModel`, `DetailsViewModel`, `HistoryScreen`, `DetailsScreen`; `androidApp/feature-history/build.gradle.kts` `minBound`; `tm-testing`.

### test-feature-route
- Type: task
- Area: androidApp/feature-route
- Priority: soon
- Source: chat 2026-10-01
- Problem: Coverage is low. The module has `RouteViewModelTest`, but its Kover floor is only `minBound(22)`.
- Done when: real tests for its ViewModel/UI logic land, and the module's Kover floor is raised in the same PR. One PR for this module only.
- Refs: `androidApp/feature-route` `RouteViewModel`, `RouteScreen`; `androidApp/feature-route/build.gradle.kts` `minBound`; `tm-testing`.

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

### tracking-finish-saves-twice
- Type: task
- Area: androidApp/feature-tracking
- Priority: soon
- Source: test-feature-tracking PR
- Problem: `TrackingViewModel.finish` saves whenever the session state is `Finished` and never records that it already saved. A second `TrackingAction.Finish` (for example a double tap on the route-completed Finish button, whose `map.snapshot` callback is asynchronous, before the `Saved` navigation runs) saves a second `ActivityRecord` and sends a second `Saved`. Pinned by `TrackingViewModelTest` "finishing twice currently saves the activity twice". Not reproduced on a device.
- Done when: a repeated `Finish` for the same session saves at most once (and sends `Saved` at most once), and that pinned test is changed to assert it.
- Refs: `androidApp/feature-tracking` `TrackingViewModel.finish`, `TrackingScreen` (Finish button, `TrackingEvent.Saved` handling); `TrackingViewModelTest`.

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
- Problem: After the JVM tests, `feature-tracking` is at 30.02% line coverage (130/433). `TrackingViewModel`, `RouteCompletionTracker` and `di/TrackingUiModule` are fully covered; everything left is Android-framework code with 0% covered: `TrackingScreen` (284 lines: `TrackingRoot`'s event handling and permission flow, both `TrackingScreen` overloads, `MetricsDisplay`, the preview, `hasLocationPermission`) and `util/MapSnapshotSaver` (19 lines: `saveSnapshotToFile` scaling, PNG write and `IOException` path). They need Robolectric and/or compose-ui-test, which are not in `gradle/libs.versions.toml`.
- Done when: an explicit task adds Robolectric/compose-ui-test to the catalog, `TrackingScreen` and `saveSnapshotToFile` have tests, and the module's Kover floor is raised in the same PR.
- Refs: `androidApp/feature-tracking` `TrackingScreen`, `MetricsDisplay`, `util/MapSnapshotSaver.kt`; `androidApp/feature-tracking/build.gradle.kts` `minBound`; `tm-testing` ("Compose UI tests", "What's actually available today").

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
