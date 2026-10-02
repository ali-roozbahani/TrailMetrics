# Epic: MVI presentation migration (Android) + first iOS ViewModel tests

- **Slug:** mvi-presentation-migration
- **Integration branch:** feature/epic/mvi-presentation-migration (only if run as an epic, see "Epic or single task?")
- **Goal:** All four Android ViewModels (Route, Tracking, History, Details) expose
  `StateFlow<State>` + `onAction(Action)` + `Channel`-backed `Flow<Event>`, each screen
  is split into Root (ViewModel, events) and Screen (pure `state` + `onAction`), and
  tests pin that the observable behavior is the same as before. Separately, the three
  iOS ViewModel files (Route, Tracking, History+Details) get their first XCTest suites,
  which sets the Swift testing pattern for the repo. The user sees no change on either
  platform.
- **Out of scope:** any change to `domain`, `data`, `core`, `shared`; `androidApp/app/**`
  (incl. `MainActivity.kt` NavHost calls) and `androidApp/core-ui/**`;
  `iosApp/TrailMetrics/**`, `iosApp/TrailMetrics.xcodeproj/**`, `iosApp/TrackingWidget/**`;
  any iOS production code (`iosApp/Packages/*/Sources/**`); navigation on either platform;
  UI redesign; `gradle/libs.versions.toml`, `settings.gradle.kts`; new third-party
  dependencies (no MockK, no Turbine, see Assumptions); gate, hook, CI, lint config.
- **Approved by:** Ali Roozbahani on 2026-09-29

## Epic or single task?

Checked against epic-orchestration's three conditions, all of which must hold:

| Condition | Holds? | Why |
|---|---|---|
| Spans ≥2 of shared / Android UI / iOS UI | Only literally | Android UI: yes. iOS: test files + each package's `Package.swift` under `iosApp/`, no iOS UI change. No shared change. |
| Splits into disjoint parallel subtasks | Yes | One Android feature module or one iOS package per subtask. No contract subtask, because nothing new is needed from the shared layer. |
| `main` shouldn't hold the half-built state | **No** | Every subtask is independently behavior-preserving and shippable. A half-migrated Android presentation layer is the state `main` is already in by design (CLAUDE.md: "migration in progress"). The iOS tests don't depend on the Android work, and the Android work doesn't depend on them. |

**Verdict: not an epic.** The iOS testing work doesn't change the answer. It adds a
second platform on paper, but it has no dependency in either direction with the Android
work, and it doesn't leave `main` half-built at any point. The skill's "Use a single task
(or a chain of ordinary PRs against `main`)" branch applies.

**Recommendation:** run the subtasks below as a chain of ordinary PRs against `main`,
using the same split, waves and acceptance criteria. This file then serves as the task
list; it doesn't need to be committed under `docs/epics/`. If the human still wants an
epic (e.g. to rehearse the process on low-risk work), the plan works unchanged: set every
subtask's base to `feature/epic/mvi-presentation-migration`. The "Epic integration
branches" ruleset is already active (checked 2026-09-29).

## Subtasks

```yaml
- id: A1
  title: Migrate RouteViewModel and RouteScreen to MVI
  branch: chore/mvi-presentation-migration-android-route
  skills: [tm-android, tm-testing, tm-pr-workflow]
  depends_on: []
  allowed_paths:
    - androidApp/feature-route/**
  acceptance:
    - Commit 1 (characterization) adds androidApp/feature-route/src/test/** with JUnit4 +
      kotlin.test + kotlinx-coroutines-test tests against the CURRENT public API
      (onMapTapped, onGenerateRouteClicked, onResetClicked, onWaypointRemoved,
      onActivityTypeSelected, saveUserProfile, onStartTrackingClicked,
      onLocationPermissionGranted, init loading). They cover at least: waypoint order
      renumbering on removal; generatedRoute cleared on removal; canGenerateRoute
      threshold; generate success/RouteError paths (isLoading, ShowError);
      MissingLocationPermission → ShowError then RequestLocationPermission, in that
      order; Start with no profile → RequestUserProfile; Start with profile and route →
      NavigateToTracking with the same payload; Reset restores defaults and reloads
      location + profile. The tests pass on the unmodified ViewModel.
    - Commit 2 migrates to RouteState / RouteAction / RouteEvent, `val state`,
      `fun onAction(action)`, `val events` (Channel-backed); no other public methods.
      The characterization tests are translated 1:1 to onAction (same inputs, same
      assertions). The PR lists the old test → new test mapping.
    - The public `RouteScreen(onStartTrackingClicked, bottomBar)` call in MainActivity
      compiles unchanged. It delegates to RouteRoot (koinViewModel, event collection,
      permission launcher, snackbar), which renders a pure RouteScreen(state, onAction, ...)
      with a @Preview in TrailMetricsTheme.
    - Collaborators are hand-written fakes of the domain interfaces (UserProfileRepository,
      LocationRepository, DirectionsRepository) in feature-route's test sources; the real
      use cases are constructed around them.
    - routeModule stays behavior-identical (switching to viewModelOf is allowed, not required).
  tier2: >
    Android emulator: plan a route (3+ taps, remove one waypoint, generate), deny then grant
    location permission, reset, start tracking with and without a saved profile. Everything
    behaves exactly as on main.

- id: A2
  title: Migrate HistoryViewModel and DetailsViewModel and their screens to MVI
  branch: chore/mvi-presentation-migration-android-history
  skills: [tm-android, tm-testing, tm-pr-workflow]
  depends_on: [A1]
  allowed_paths:
    - androidApp/feature-history/**
  acceptance:
    - Same two-commit structure as A1. The characterization tests pin: History loading →
      list → isEmpty; delete removes the record and its snapshot file; Details loads the
      activity by id; deletion removes the record + snapshot and then signals completion
      exactly once.
    - History: HistoryState / HistoryAction / HistoryEvent. The row click goes through
      HistoryAction.ActivityClicked(id) → HistoryEvent.NavigateToDetails(id), so that the
      ViewModel exposes an Event (DoD) without changing what the user sees.
    - Details: onDeleteConfirmed(onDeleted) is replaced by DetailsAction.DeleteConfirmed →
      DetailsEvent.Deleted, which DetailsRoot turns into onNavigateBack. The delete dialog's
      visibility stays view-local `remember` state.
    - The MainActivity calls `HistoryScreen(onActivityClicked, bottomBar)` and
      `DetailsScreen(activityId, onNavigateBack)` compile unchanged.
    - FakeActivityHistoryRepository lives in feature-history's test sources.
  tier2: >
    Android emulator: History with 0 and 2+ activities; open details; delete from the list;
    delete from details (returns to the list, record gone). Same as on main.

- id: A3
  title: Migrate TrackingViewModel and TrackingScreen to MVI; move route completion out of composition
  branch: chore/mvi-presentation-migration-android-tracking
  skills: [tm-android, tm-testing, tm-pr-workflow]
  depends_on: [A1]
  allowed_paths:
    - androidApp/feature-tracking/**
  acceptance:
    - Same two-commit structure as A1. The characterization tests drive a real
      TrackingSessionManager built from fakes (LocationRepository, TrackingServiceLauncher,
      Clock, Logger) and the TestScope, and pin: start/pause/resume/stop state
      transitions; the calorie computation (null without profile or average speed);
      Finish saves with startedAtEpochMillis from the Clock at Start, and saves only in
      Finished with a profile; the locationIssues mapping (MissingLocationPermission →
      RequestLocationPermission, otherwise ShowError).
    - A characterization test for route completion is written against the CURRENT rule
      (ROUTE_COMPLETION_INDEX_MARGIN, ROUTE_COMPLETION_THRESHOLD_METERS, only while
      Tracking, fires once) BEFORE it moves.
    - Target shape as in tm-android's TrackingAction/TrackingEvent example. The UI-state
      class is renamed so that it doesn't collide with domain TrackingState.
      onFinishClicked(path, onSaved) becomes Action.Finish(path) → Event.Saved.
      startedAtEpochMillis is no longer a public or loose mutable field.
    - Route progress (calculateRouteProgress from domain, the lastProgressIndex carry-over)
      and the completion check move into the ViewModel. Progress is exposed in State, and
      completion calls stop() from the ViewModel. TrackingScreen keeps no `remember`
      progress/completion state and calls no stop from a LaunchedEffect. Same thresholds,
      same once-only semantics.
    - The MainActivity call `TrackingScreen(initialStartPoint, plannedRoutePoints,
      activityType, onNavigateBack)` compiles unchanged.
    - No domain change: calculateRouteProgress is used as is.
  tier2: >
    Android emulator with a GPX/mock-location route: start, pause, resume, stop, finish
    (saved and navigates back); walk a planned route to its end → tracking auto-stops once;
    deny location permission. Also rotate mid-route (see Assumptions: progress now survives
    rotation).

- id: I1
  title: Add the first iOS ViewModel tests (History + Details) and establish the Swift test pattern
  branch: chore/mvi-presentation-migration-ios-history-tests
  skills: [tm-ios, tm-testing, tm-pr-workflow]
  depends_on: []
  allowed_paths:
    - iosApp/Packages/History/Package.swift
    - iosApp/Packages/History/Tests/**
  acceptance:
    - A `.testTarget(name: "HistoryTests", dependencies: ["History"])` is added. No new
      package dependencies, and Package.resolved is unchanged.
    - XCTest, `@MainActor` test classes, hand-written Swift fakes conforming to the
      exported Kotlin protocols (e.g. ActivityHistoryRepository), no mocking library.
      Test names follow tm-ios: `test_<subject>_<expectation>()`.
    - It covers HistoryViewModel (observe → activities/isLoading, onDeleteActivity) and
      DetailsViewModel (load by id, onDeleteConfirmed deletes and calls onDeleted once).
    - The fakes directory and the async-waiting helper form the documented pattern (a
      short header comment in the fakes file) that I2/I3 copy.
    - `xcodebuild test -scheme History -destination 'platform=iOS Simulator,...'` (run from
      iosApp/Packages/History) passes. The agent runs it, because the gate doesn't (see
      Assumptions), and pastes the command and the result into Tier 1. SwiftLint --strict
      passes over the new test files.
    - Feasibility stop condition: if faking a Flow-returning member (observeActivities())
      from Swift can't be done without a Kotlin/shared helper, stop and report. Don't touch
      shared/ or any Sources/ file.
    - No file under Sources/ changes.
  tier2: none — tests only, no production change

- id: I2
  title: Add iOS RouteViewModel tests
  branch: chore/mvi-presentation-migration-ios-route-tests
  skills: [tm-ios, tm-testing, tm-pr-workflow]
  depends_on: [I1]
  allowed_paths:
    - iosApp/Packages/Route/Package.swift
    - iosApp/Packages/Route/Tests/**
  acceptance:
    - Follows the pattern merged in I1 exactly (framework, fake style, waiting helper, naming).
    - Real GetCurrentLocationUseCase / GenerateClosedRouteUseCase built around Swift fakes
      of LocationRepository / DirectionsRepository; fake UserProfileRepository.
    - It covers the same behaviors as A1's list where the iOS ViewModel has them, including
      makeEventsStream() returning a fresh, working stream on a second call.
    - `xcodebuild test -scheme Route` passes (run by the agent, reported). SwiftLint passes.
      No Sources/ change.
  tier2: none — tests only

- id: I3
  title: Add iOS TrackingViewModel tests
  branch: chore/mvi-presentation-migration-ios-tracking-tests
  skills: [tm-ios, tm-testing, tm-pr-workflow]
  depends_on: [I1]
  allowed_paths:
    - iosApp/Packages/Tracking/Package.swift
    - iosApp/Packages/Tracking/Tests/**
  acceptance:
    - Follows I1's pattern exactly.
    - Real TrackingSessionManager built from Swift fakes + a CoroutineScope obtainable from
      Swift; real CalorieCalculator; fake Clock/UserProfileRepository; SaveActivityUseCase
      around a fake ActivityHistoryRepository.
    - It covers the state transitions, the calories recompute, onFinishClicked saving and
      calling onSaved once, and the locationIssues → UiEvent mapping.
    - Stop condition: if a CoroutineScope can't be obtained from Swift without a shared/
      change, cover what's reachable, stop, and report the rest as a Follow-up.
    - `xcodebuild test -scheme Tracking` passes (run by the agent, reported). SwiftLint
      passes. No Sources/ change.
  tier2: none — tests only
```

## Waves

- Wave 1: A1 ∥ I1   (disjoint: `androidApp/feature-route/**` vs `iosApp/Packages/History/{Package.swift,Tests/**}`.
  Each one sets its platform's pattern, so the others wait for it.)
- Wave 2: A2 ∥ A3 ∥ I2 ∥ I3   (disjoint: one feature module or one iOS package each; none
  touches `app/`, `core-ui/`, the version catalog, the xcodeproj or the shared layer)

Execution: sequential in the main checkout by default. Worktree parallelism is possible
now (see Drift found), but only if the human opts in. Four concurrent Gradle + xcodebuild
gates on one machine is heavy.

## Tier 2 on the integrated result (or on main after the last PR)

- Android: the full flow Route → Tracking (to auto-completion) → Finish → History →
  Details → delete, with the same behavior as on the pre-migration build.
- iOS: nothing to check on a device. Production code is unchanged; `git diff` shows no
  `iosApp/Packages/*/Sources/**` or `iosApp/TrailMetrics/**` change.

## Assumptions

1. **No MockK, no Turbine.** tm-testing prescribes both, but neither is in
   `libs.versions.toml`, and CLAUDE.md forbids adding a third-party dependency the task
   doesn't name. Tests use JUnit4 + `kotlin.test` + `kotlinx-coroutines-test` (all
   already in the catalog), hand-written fakes, and `backgroundScope` collection instead
   of Turbine. Each feature module adds only `testImplementation` lines for existing
   catalog entries to its own `build.gradle.kts`.
2. **"Same behavior" is proven by characterization tests first.** They are written
   against the old API, shown green on the old code (commit 1), then translated 1:1 to
   `onAction` (commit 2). That departs from tm-testing's "don't write tests against
   onXClicked methods", which assumes a spec-first migration; here the DoD asks for
   before/after equivalence. Squash merge keeps only the result, so the PR description
   carries the mapping.
3. **"Signature unchanged" means the NavHost call sites.** The public `XScreen(<nav
   params>)` entry points keep their names and parameters and delegate to `XRoot`. The
   unused `viewModel: XViewModel = koinViewModel()` default parameter is removed:
   tm-android forbids a ViewModel parameter below the Root, and NavHost never passes it.
   The pure composable is an `XScreen(state, onAction, …)` overload. Switching
   MainActivity to call `XRoot` directly and deleting the forwarders is a Follow-up that
   touches `androidApp/app/**`.
4. **Moving route progress into the ViewModel makes it survive configuration changes**,
   where `remember` did not. That is the only observable difference: an auto-stop can no
   longer fire twice after a rotation. It's treated as within "fix it when you touch it".
5. **XCTest over Swift Testing.** tm-ios's test-name convention (`func test_…()`) is XCTest
   style, it works with `swift-tools-version: 5.9` unchanged, and it needs no toolchain
   decision.
6. **Swift tests are not run by the gate or CI.** Both do `xcodebuild build` of the app
   scheme only, and that doesn't compile package test targets. Changing that means
   touching `scripts/pre-push-check.sh` and `.github/workflows/ci.yml`, which is out of
   scope here. See Follow-ups.
7. Duplicate fakes per Android feature module (e.g. `FakeUserProfileRepository` in both
   route and tracking) are accepted. A shared test-fixtures module would need
   `settings.gradle.kts` and a new module.

## Follow-ups (not in this plan)

- `chore(ci)`: run `xcodebuild test` for each iOS package with tests in the gate and in
  CI's iOS job. Until then the I1–I3 tests are enforced only by the agent's and
  reviewers' manual runs.
- Switch MainActivity to `XRoot` and drop the `XScreen` forwarders (touches `androidApp/app/**`).
- iOS has no route-completion auto-stop equivalent. If parity is wanted, the rule belongs
  in `domain` (tm-android: "or domain, if iOS needs it too"), which would be a shared change.

## Drift found (skills vs repo, 2026-09-29)

- epic-orchestration says worktrees can't pass the gate/hook. #40 already made both
  resolve the marker with `git rev-parse --git-path`, so that section is stale.
- tm-testing prescribes Turbine and MockK, but neither is in the version catalog, and no
  `androidApp` module has test dependencies.
- tm-android names the Root `<Screen>Root`. Without touching MainActivity, that can only
  be done with a forwarder (Assumption 3).
