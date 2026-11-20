# Epic: Route completion to `domain`, run by `TrackingSessionManager`

- **Slug:** route-completion-to-domain
- **Integration branch:** feature/epic/route-completion-to-domain
- **Goal:** the route counts as completed in one place, `domain`, and `TrackingSessionManager` runs the detection, so a session ends at
  the end of the planned route on both platforms whatever the UI is doing: also with the phone locked and the screen off. The
  ViewModels and screens only show the result: `TrackingView.swift` renders only, and Android's `withRouteCompletion`,
  `RouteCompletionTracker` and `hasReachedDestination` are gone (the finish card follows `canSave`). `calculateRouteProgress` does not throw
  for an out-of-range input.
- **Out of scope:** the thresholds (25 m, last 3 points: decision 3); progress of a restored session (it starts from index 0 again:
  decision 4); persisting progress across process death; the map drawing; the notification that tells the user a session ended by itself
  (decision 5: its own task after this epic is merged, see `Source` of its board record `session-ended-by-itself-notification`); a
  discard control for a finished session (board record `finished-session-discard-control`); any change to `BOARD.md` by a subtask (the
  orchestrator's board commit at the end of the run does that, on the integration branch).
- **Approved by:** the owner, 2026-11-19, with the answers of "Decisions of the owner" below (recorded here from the owner's decisions
  given for this update). The owner decided on 2026-11-19 that this runs as an epic by `epic-orchestration`. The owner still merges the
  PR that adds this plan to `main` (`/docs/epics/` is a protected path), and the epic PR into `main`: the one PR of the run.

- **Status:** done. Was: plan, approved 2026-11-19. This file is on `main` before the integration branch exists. The orchestrator's last commit on the
  integration branch (the board commit) sets this line to `done`, so it reaches `main` with the epic PR and the owner has no extra merge for it.
  The live state of a run is on the integration branch and in the run record (section "How this epic is run"), never in this file.
- **Source:** BOARD.md record `route-completion-to-domain` (Order 60).

## Correction (what the first version of this plan got wrong)

The first version of Question 1 and Risk 1 said that with Option A (completion in the UI layer, inside a domain
tracker) iOS would auto-stop with a locked screen "as Android does". That is false. On Android the screen state is
`combine(...).map(::withRouteCompletion).stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000))` and the screen
collects it with `collectAsStateWithLifecycle`, so once the screen is locked or the app is in the background for more
than 5 seconds nothing collects, the pipeline stops, and `withRouteCompletion` does not run: Android does not complete the
route while locked. On iOS `TrackingViewModel` starts `observeTrackingState()` in `init`, not in the View, so after moving
the logic into that ViewModel (Option A) iOS would have completed while locked and Android would not. Option A would
have created a new difference between the platforms, the opposite of the epic's goal. The owner chose Option B: the
detection runs in `TrackingSessionManager`, which both platforms share and which keeps running (Android: the foreground
service; iOS: background location) whatever the UI does.

## 1. What the code does today

Facts below are read from `main` at 3c93063c. PR #358 (the tracking control rules, merged after the first version of this plan was
written) changes two lines the plan names: the finish card condition reads `state.canSave` instead of
`state.trackingState is TrackingState.Finished` on Android, and iOS's `canFinish` is `canSave && !isDiscarding`. Where this plan says
`Finished`, it holds either way.

### Shared (`domain`)

`domain/.../model/RouteProgress.kt` holds `RouteProgress(traveledSegment, remainingSegment, lastIndex)` and
`calculateRouteProgress(plannedRoute, currentLocation, previousIndex = 0, searchWindow = 10)`. It returns the
planned point closest to the location inside `previousIndex..(previousIndex + searchWindow)`, so progress never
moves backwards. It has no guard: with `previousIndex >= plannedRoute.size` the range is empty,
`minByOrNull` gives null, `closestIndex` becomes `previousIndex` and `subList(0, closestIndex + 1)` throws; with
a negative `previousIndex` `plannedRoute[index]` throws. Neither platform can reach this today, because
`lastIndex` always comes from the same unchanged planned route, which is why the defect has not shown.
`RouteProgressTest` has 5 cases and none for this.

The completion rule is **not** in `domain`.

### Android

`androidApp/feature-tracking/.../RouteCompletionTracker.kt` (`internal`, 57 lines) holds `progress`,
`hasReachedDestination` (a latch), `lastProgressIndex` and `lastLocation`. `onUpdate(currentLocation, trackingState)`:

1. recalculates progress only when the location changed (`currentLocation != lastLocation`), from
   `lastProgressIndex`, with the default window of 10;
2. decides completion: location not null, planned route not empty, state is `Tracking`, progress not null,
   `lastIndex >= size - 3` and `currentLocation.distanceTo(plannedRoutePoints.last()) <= 25.0`;
3. returns true exactly once (the latch).

`TrackingViewModel.withRouteCompletion` calls it inside
`combine(...).map(::withRouteCompletion).stateIn(viewModelScope, WhileSubscribed(5_000))`, with
`state.currentPath.lastOrNull()` (the path of `Tracking`, `Paused` and `Finished`), and on true calls
`trackingSessionManager.stop()`. It copies `routeProgress` and `hasReachedDestination` into
`TrackingScreenState`. The screen shows the finish card when
`state.hasReachedDestination || state.trackingState is TrackingState.Finished` (`TrackingScreen.kt`, the `AnimatedContent` target).

Tests: `RouteCompletionTrackerTest` (19 cases: thresholds pinned, empty route, no progress before a
location, progress never backwards, same location twice, stops exactly once, third-to-last point,
a point before the last three, past the end inside and outside the threshold, the start of a closed
loop, paused at the end, idle and finished, exactly at and just beyond 25 m) and four in
`TrackingViewModelTest` ("route progress follows location updates", "reaching the end of the planned route
stops tracking and keeps the progress", "reaching the end again in a later session does not stop a second
time" and "a session stopped at the route end can be finished and saved").

### iOS

All of it is in the View. `TrackingView.swift` holds `@State routeProgress`, `lastProgressIndex`
(`Int32`) and `hasReachedDestination`, the two constants `routeCompletionIndexMargin = 3` and
`routeCompletionThresholdMeters = 25.0`, a computed `isRouteCompleted` (same five conditions as Android,
reading `viewModel.currentPath.last`, `viewModel.plannedRoutePoints`, the `.tracking` case and `routeProgress`)
and `updateRouteProgress()` (calls `calculateRouteProgress(... previousIndex: lastProgressIndex, searchWindow: 10)`).
Triggers: `.onChange(of: viewModel.currentPath) { updateRouteProgress() }` and
`.onChange(of: isRouteCompleted) { if completed && !hasReachedDestination { hasReachedDestination = true; viewModel.onStopClicked() } }`.
The card shows when `hasReachedDestination || viewModel.canFinish` (`TrackingView.swift`, in `body`).

Tests: none in a Swift package (a View cannot be unit tested with the fakes). The only coverage is the UI test
`TrackingFinishTwiceUITests` (the fixture walk reaches the end and the "Finish" button appears) and
the iOS-side `UiTestFakesTest` in `shared-uitest` (it calls `calculateRouteProgress` to check that the fixture walk ends inside the radius).

### Differences between the platforms

| # | Aspect | Android | iOS | Effect today |
|---|---|---|---|---|
| D1 | Where the decision lives | `RouteCompletionTracker` in `feature-tracking`, owned by the ViewModel | the View (`TrackingView`), 3 `@State` values and 2 duplicated constants | iOS is untestable; the rule can drift (it has not yet: both use 25.0 and 3) |
| D2 | What triggers it | every emission of the combined state while the screen collects it (`collectAsStateWithLifecycle`, then the 5 s grace of `WhileSubscribed`); `stop()` is called as a side effect inside a flow `map`. **With the screen locked nothing runs.** | SwiftUI `onChange` of `currentPath` and of `isRouteCompleted`, so only while the view is rendering. The ViewModel's own state observation runs from `init`, but the completion decision is not in it | with the screen locked Android does not complete the route (the pipeline is stopped); iOS completes only if the view still renders. No test shows either. Both are replaced by completion in the manager (section 2) |
| D3 | Which path feeds the location | `currentPath` of `Tracking`, `Paused` and `Finished` | `currentPath` of `Tracking` and `Paused` only (`Finished` gives `[]`) | none visible: a `Finished` session produces no new location, and both keep the last progress |
| D4 | What "stop" does at the end | `trackingSessionManager.stop()` | `viewModel.onStopClicked()`: cancels the observation tasks, reads the state back, ends the Live Activity | platform part (Live Activity). Stays on iOS |
| D5 | Lifetime of the latch and the index | the ViewModel (survives rotation) | the view's `@State` (one view per screen) | none: one screen, one session |
| D6 | `searchWindow` | the default (10) | an explicit 10 | the same value, written twice |
| D7 | Index type | `Int` | `Int32` | none |
| D8 | Test coverage | 19 + 4 cases | 0 unit cases, 1 UI test | iOS completion is unprotected |

No difference changes what the user sees in a normal walk with the screen on. D2 is the one that matters with the screen off, and it is
what the owner's decision 1 changes on both platforms on purpose (S2).

### Finding: a route passed while the phone is locked

Today, on Android, a user who reaches or passes the end of the route while the screen is locked is not detected at that time, and
may never be. After unlocking, `RouteCompletionTracker` starts again from its last index (0 on a new ViewModel, and the
last index it had before the pipeline stopped otherwise), looks at the **latest** location only, moves progress by at most the window
of 10 route points per **changed** location, and completes only if the state is `Tracking`, progress is within the last 3 points and the
location is within 25 m of the last point. So: a user who walked past the end and away is never completed; a user who stands still at
the end after unlocking gets no new location and so no progress step; a user who keeps moving near the end completes only after enough
fixes have caught the progress up. The same holds on iOS whenever the view did not render. This is the rule as it is written, not a
bug in one line, and the plan does not change a threshold for it. What changes is where it runs: in the manager it sees every fix, so
progress advances at each fix (still by at most 10 points each) and the end is detected when the user is there. A caveat that remains
for the owner to know: progress moves by at most 10 route points per fix, so a very dense planned route with a fast mover could lag;
the polylines `DirectionsRepositoryImpl` returns, at walking and cycling speed and about one fix a second, do not reach that limit by
our reading; no test shows it, and the plan does not change the window.

## 2. Target design (Option B, the owner's decision 1)

**Moves to `domain`:**

1. `calculateRouteProgress` gets a guard: `previousIndex` is clamped to `0..plannedRoute.lastIndex`, a negative `searchWindow`
   counts as 0. It returns the same values for every input that is valid today.
2. A new class `dev.roozbahani.trailmetrics.domain.tracking.RouteCompletionTracker(plannedRoute: List<Coordinates>)`, ported from
   Android's, public, with the two constants private to it. It is stateful (index, last location, the once-only latch) and is not
   thread-safe; the manager uses it from one coroutine only (below), and the KDoc says so.

   ```kotlin
   class RouteCompletionTracker(plannedRoute: List<Coordinates>) {
       fun update(location: Coordinates, state: TrackingState): RouteCompletionUpdate
   }
   data class RouteCompletionUpdate(val progress: RouteProgress, val reachedNow: Boolean) // reachedNow: true exactly once
   ```

3. `TrackingSessionManager` owns one tracker per session and runs it. It creates the tracker in `start(..., plannedRoute)` and in
   `restore()` (from `SessionDetails.plannedRoute`; progress starts from index 0, decision 4), and calls `update` in its location
   collector right after it dispatches each `LocationReceived`. On `reachedNow` it calls its own `stop()` (the state becomes
   `Finished`, the launcher stops, the stored session stays until it is saved: the same result as Android's `stop()` today). It exposes
   `routeProgress: StateFlow<RouteProgress?>` (null before the first fix and with no plan). `stop()` becomes idempotent: in `Idle` and
   `Finished` it does nothing (no event, no launcher call). That is what keeps the Android and iOS code that still calls `stop()` at the
   route's end green until S4 and S5 remove it. The constructor and the Koin graph do not change: the tracker is built inside. A new
   session after `discard()` gets a new tracker.

   Evaluated at each fix and nowhere else: a resume at the route's end completes at the first fix after the resume, not at the
   resume itself (the old Android rule evaluated at the next state emission). The tracker is touched only inside the collector
   coroutine (`observeLocation` cancels the previous one first), so it needs no lock.

**Stays in the platforms:**

- What the UI does with the result: Android's `TrackingViewModel` puts `routeProgress` into `TrackingScreenState`; iOS's
  `TrackingViewModel` publishes it. The finish card follows `canSave` (decision 2).
- The iOS Live Activity: it ends when the observed state turns `Finished`, whoever caused it (S3). Android's equivalent is the foreground
  service, which the manager's `stop()` already stops through `TrackingServiceLauncher`.
- Drawing the traveled segment, the camera, the card.

**Why Option B:** the decision "the session is at the end of its route" is a rule about the session, not about a screen; the
manager already holds the plan and sees every fix, and it keeps running when the UI does not (the Android foreground service, iOS
background location). Option A would have kept the rule in the UI layer, where the two platforms stop at different moments (the
Correction). `tm-kmp-shared`, "Where logic lives": derived state and rules both platforms need are in `domain`, tested once, and
ViewModels only adapt.

**Why an epic, and why this slicing:** the owner decided on 2026-11-19 that this runs as an epic, with the subtasks merged locally (section "How this epic is run"). The work moves between `domain`, Android and
iOS, and `main` should not hold a half-built state: between the manager ending sessions (S2) and the iOS cleanup (S5) the iOS Live Activity
is ended by the S3 observation and the View's own detection is redundant, which is fine on an integration branch and would be a chain of
careful interim states on `main`. Domain work has one owner at a time (hotspot rule): S1 then S2. The iOS Live Activity preparation (S3) and the
domain guard (S1) touch disjoint files and run together. After the contract (S2), the Android and iOS sides are disjoint and run together.

## Subtasks

A subtask is not a PR: its `branch` is a local branch that the orchestrator creates from the integration branch, builds with a worker, reviews and gates
locally, and merges locally into `feature/epic/route-completion-to-domain`. These branches are never pushed.

```yaml
- id: S1
  title: Guard calculateRouteProgress against an out-of-range index
  branch: bugfix/route-completion-to-domain-progress-guard
  skills: [tm-kmp-shared, tm-testing, tm-robustness]
  depends_on: []
  allowed_paths:
    - domain/src/commonMain/kotlin/dev/roozbahani/trailmetrics/domain/model/RouteProgress.kt
    - domain/src/commonTest/kotlin/dev/roozbahani/trailmetrics/domain/model/RouteProgressTest.kt
  acceptance:
    - calculateRouteProgress does not throw for a previousIndex equal to or above plannedRoute.size, for a negative previousIndex, for a
      negative searchWindow, or for a one-point route with previousIndex 3; the result for each is the clamped one (previousIndex
      clamped to 0..lastIndex, a negative searchWindow counted as 0).
    - The result for every input that is valid today is unchanged.
    - The KDoc says what is clamped.
    - Red test first (tm-testing, "Bugfixes: red test first"): the commit message names the failing test and its failure on the unfixed code.
  tier2: none user-visible. RouteProgressTest, new cases written first and red on the unfixed code (`previousIndex at the size does not
    throw`, `previousIndex past the size does not throw`, `negative previousIndex does not throw`, `negative searchWindow counts as zero`,
    `one-point route with a large previousIndex does not throw`, `valid input keeps its result`); the 5 existing cases stay green unchanged.

- id: S2
  title: Domain RouteCompletionTracker, run by TrackingSessionManager, which ends the session at the route's end
  branch: feature/route-completion-to-domain-session-ends
  skills: [tm-kmp-shared, tm-testing, tm-robustness]
  depends_on: [S1]
  allowed_paths:
    - domain/src/commonMain/kotlin/dev/roozbahani/trailmetrics/domain/tracking/RouteCompletionTracker.kt
    - domain/src/commonMain/kotlin/dev/roozbahani/trailmetrics/domain/tracking/TrackingSessionManager.kt
    - domain/src/commonTest/kotlin/dev/roozbahani/trailmetrics/domain/tracking/RouteCompletionTrackerTest.kt
    - domain/src/commonTest/kotlin/dev/roozbahani/trailmetrics/domain/tracking/TrackingSessionManagerRouteCompletionTest.kt
    - domain/src/commonTest/kotlin/dev/roozbahani/trailmetrics/domain/fakes/**
    - domain/README.md
    - domain/src/commonTest/kotlin/dev/roozbahani/trailmetrics/domain/tracking/TrackingSessionManagerPersistenceTest.kt
    - config/kover-floors.properties
  acceptance:
    - RouteCompletionTracker is public in dev.roozbahani.trailmetrics.domain.tracking with update(location, state) returning
      RouteCompletionUpdate(progress, reachedNow); reachedNow is true exactly once; the two constants are private and the rule is the
      Android one unchanged (25.0 m, progress index at least size - 3, state Tracking, a non-empty plan, never completes without a plan).
    - TrackingSessionManager creates a tracker in start(..., plannedRoute) and in restore() (index 0), evaluates it after each
      LocationReceived and nowhere else, calls its own stop() on reachedNow, and exposes routeProgress as a StateFlow (null before the first
      fix and without a plan). A new session gets a new tracker.
    - stop() is idempotent: in Idle and Finished it does nothing (no event, no launcher call).
    - The session ends by itself with no collector of any flow: fixes along the plan end with currentState Finished, the launcher stopped
      once, the stored session kept (not cleared), and the session path ends with the fix that completed it.
    - The constructor of TrackingSessionManager and the Koin graph do not change (the KoinGraph tests of shared stay green unchanged).
    - No file under androidApp/ or iosApp/ changes; every existing Android and iOS test stays green unchanged (the gate runs them), judged on the combination of S2 and S4: S2 and S4 are one integration unit (owner's decision of 2026-11-20), each reviewed on its own, gated once on the two together, and merged into the integration branch with its own `Epic-Subtask` trailer, S2 first. The only Android tests that change are the three S4 names (they change in S4, not in S2).
    - The domain Kover floor is raised by the ratchet rule, to the measured coverage minus 1 to 2 points, rounded down.
  tier2: domain commonTest, kotlin.test, on the Android host and the iOS simulator. RouteCompletionTrackerTest has the 19 cases of Android's
    RouteCompletionTrackerTest, same names, adapted to update/RouteCompletionUpdate (thresholds pinned, empty plan, no progress before a
    location, progress never backwards, same location twice, completes exactly once, third-to-last point, a point before the last three, past
    the end inside and outside the threshold, the start of a closed loop, paused at the end, idle and finished, exactly at and just beyond
    25 m). TrackingSessionManagerRouteCompletionTest: `the session ends at the route's end with nobody collecting any flow`, `progress
    advances with each fix while nothing collects`, `a plan-less session never ends by itself`, `a paused session does not end until the first
    fix after resume`, `the session ends once, not at each later fix`, `a second session after discard ends again`, `a restored session
    starts progress from index 0`, `the completing fix is the last point of the path`, `stop is a no-op in idle and finished`. The existing
    TrackingSessionManagerTest and TrackingSessionManagerPersistenceTest cases stay green unchanged, except one (owner's decision of 2026-11-20): `start on a planned route keeps the plan in the details and saves it with every state` in TrackingSessionManagerPersistenceTest changes its fixture only, so that the fix it emits does not complete the session (farther than 25 m from the route's end); its three assertions stay exactly as they are. The same kind of change (a fixture fix that now completes the session, assertions unchanged) is allowed for any other existing test under domain/src/commonTest that is red for only that reason; every such change is listed in the epic PR's notes. Any other red test, any change to an assertion, or any test outside domain/src/commonTest is a stop. The test named `the completing fix is the last point of the path` proves that the path ends with the fix that completed the session, which is the first fix that satisfies the rule, not necessarily the last route point; the epic PR's notes say so.

- id: S3
  title: iOS ends the Live Activity whenever the observed state turns Finished
  branch: chore/route-completion-to-domain-ios-live-activity
  skills: [tm-ios, tm-testing, tm-robustness]
  depends_on: []
  allowed_paths:
    - iosApp/Packages/Tracking/Sources/Tracking/TrackingViewModel.swift
    - iosApp/Packages/Tracking/Sources/Tracking/TrackingLiveActivityController.swift
    - iosApp/Packages/Tracking/Tests/**
  acceptance:
    - When TrackingViewModel observes the state turn Finished, it ends the Live Activity with the final distance, time and speed, whether
      or not onStopClicked() ran.
    - The Live Activity is ended once per session even though onStopClicked() also ends it.
    - Nothing else changes for the user: Stop, Stop and Exit and the Live Activity's own Stop behave as before.
    - Red test first for the first case (it fails on the current code).
  tier2: XCTest in TrackingViewModelLiveActivityTests on the real TrackingViewModel over TestSupport fakes: `test_sessionFinishedByTheManager_endsTheLiveActivityOnce`
    (the session is stopped through the manager, not the ViewModel) and `test_onStopClicked_endsTheLiveActivityOnce`. Every existing
    TrackingViewModelLiveActivityTests and TrackingLiveActivityControllerTests case stays green unchanged.

- id: S4
  title: Android shows the session's route progress and end from the manager, and drops its own tracker
  branch: feature/route-completion-to-domain-android
  skills: [tm-android, tm-testing, tm-robustness]
  depends_on: [S2]
  allowed_paths:
    - androidApp/feature-tracking/**
    - .claude/skills/tm-android/SKILL.md
  acceptance:
    - TrackingViewModel puts the manager's routeProgress into TrackingScreenState; it holds no completion rule and calls no stop() for the
      route's end.
    - androidApp/feature-tracking/.../RouteCompletionTracker.kt and RouteCompletionTrackerTest.kt are deleted, and withRouteCompletion and
      hasReachedDestination are gone; the finish card follows canSave (decision 2).
    - When the manager ends the session while nobody collects the ViewModel's state (the locked screen), collecting the state afterwards
      gives Finished, canSave true and the progress at the end.
    - Existing tests change in exactly three places (owner's decision of 2026-11-20), and no other assertion changes: (1) TrackingScreenTest
      `taps on Finish before and after a slow save completes save one activity` and (2) TrackingScreenSnapshotTest `a snapshot without a bitmap
      finishes once and does not block a later tap`: after a save the session is discarded, so under decision 2 (the card follows canSave) there is no
      card and no second tap; each must still pin what it pinned (a Finish tap during a slow save saves once; a snapshot callback without a bitmap
      releases the guard so a later Finish sends a new snapshot request, shown in a scenario where the card is still shown, for example when the first
      save fails), and no assertion is deleted without equivalent coverage; (3) TrackingViewModelTest `route progress follows location updates`: the
      assertion right after Start expects no progress until the first fix (S2's contract), its assertions after the first fix stay. The three
      assertions of TrackingViewModelTest that name hasReachedDestination, and the TrackingScreenStateTest construction where it names it, change
      only where they name it. Every other existing case in feature-tracking stays green unchanged. The three changes and their reasons go in the
      epic PR's notes. Any other red test, a change of any other assertion or a change of S2's contract is a stop.
    - The feature-tracking Kover floor (92) still holds without lowering it; if it does not, stop and report (re-plan trigger).
    - The tm-android "Compose" bullet that names RouteCompletionTracker as Android's is updated to say the manager owns the rule.
  tier2: TrackingViewModelTest: `the session ends at the route's end while nobody collects the state` (new), the four existing completion cases
    adapted only where they name hasReachedDestination (`route progress follows location updates`, `reaching the end of the planned route
    stops tracking and keeps the progress`, `reaching the end again in a later session does not stop a second time`, `a session stopped at the
    route end can be finished and saved`), TrackingScreenStateTest (the card follows canSave), TrackingScreenTest and TrackingScreenSnapshotTest changed only in the one case each named above, the other Compose tests unchanged.
    The locked-screen human check is in the epic-level Tier 2.

- id: S5
  title: iOS TrackingView renders only; TrackingViewModel publishes the manager's route progress
  branch: chore/route-completion-to-domain-ios
  skills: [tm-ios, tm-testing, tm-robustness]
  depends_on: [S2, S3, S4]
  allowed_paths:
    - iosApp/Packages/Tracking/**
  acceptance:
    - TrackingViewModel observes the manager's routeProgress (for await, cancelled with the state observation) and publishes it
      (public private(set)); it holds no completion rule.
    - TrackingView loses routeProgress, lastProgressIndex, hasReachedDestination, routeCompletionIndexMargin,
      routeCompletionThresholdMeters, isRouteCompleted, updateRouteProgress and both onChange blocks; the finish card follows canFinish.
    - Reaching the route's end ends the session with no View involved: state Finished, canFinish true, launcher stop count 1, Live
      Activity ended once.
    - Red test first where it can be: the new tests do not compile before the change (the red evidence is the missing member, said plainly).
    - grep for isRouteCompleted, lastProgressIndex, routeCompletionThresholdMeters, routeCompletionIndexMargin and hasReachedDestination
      in iosApp/Packages/Tracking/Sources prints nothing.
  tier2: XCTest in TrackingViewModelTests (or a new TrackingViewModelRouteCompletionTests) on the real TrackingViewModel over TestSupport fakes:
    `test_routeProgress_followsTheFixes`, `test_reachingTheRouteEnd_finishesTheSessionWithoutAView`, `test_atTheRouteEnd_whilePaused_doesNotFinishUntilResume`,
    `test_anEmptyPlan_neverFinishes`, `test_theFinishCard_followsCanFinish`. TrackingFinishTwiceUITests (the fixture walk reaches the end and
    Finish appears), TrackingViewModelTests, SavedSessionOfferTests, TrackingViewModelClearSessionTests, TrackingViewModelFinishTests and the S3 tests
    stay green unchanged. The locked-screen human check is in the epic-level Tier 2.
```

## Waves

- Wave 1: S1 ∥ S3   (disjoint: the two domain files `RouteProgress.kt` and `RouteProgressTest.kt` vs `iosApp/Packages/Tracking/Sources/Tracking/TrackingViewModel.swift`,
  `TrackingLiveActivityController.swift` and `iosApp/Packages/Tracking/Tests/**`; checked on the globs and on the tracked files: no file matches both)
- Wave 2: the unit S2 then S4   (S2: the tracker, `TrackingSessionManager`, its tests, the fakes, the README and the Kover floor, one owner at a time; S4 starts from S2's
  branch; each is reviewed on its own, the gate runs once on the combination, both are merged into the integration branch, S2 first; owner's decision of 2026-11-20)
- Wave 3: S5   (starts after the unit is merged; `iosApp/Packages/Tracking/` only)

The waves follow from `depends_on`: S1 and S3 have none; S2 needs S1; S4 needs S2 and is gated together with it; S5 needs S2, S3 and S4 (the unit is merged first). S3 and S5 both write under
`iosApp/Packages/Tracking/` but in different waves, and S5 starts only after S3 is merged locally into the integration branch. Gates are serialized by the
heavy-run lock whatever the waves say.

## Acceptance coverage

| Goal criterion | Subtask | Check that proves it |
|---|---|---|
| `calculateRouteProgress` does not throw for out-of-range input | S1 | the new `RouteProgressTest` cases |
| the completion rule is in `domain` with `kotlin.test` coverage | S2 | `RouteCompletionTrackerTest` (19 cases), the 25 m and last-3 cases pin decision 3 |
| the session ends at the route's end with no UI subscriber, on both platforms | S2, S4, S5 | `the session ends at the route's end with nobody collecting any flow` (domain), `the session ends at the route's end while nobody collects the state` (Android), `test_reachingTheRouteEnd_finishesTheSessionWithoutAView` (iOS); the locked-screen human check |
| Android has no tracker of its own and no `hasReachedDestination` | S4 | the greps of the definition of done; the changed tests named in S4 |
| `TrackingView` renders only | S5 | the grep in S5's acceptance; `TrackingFinishTwiceUITests` green |
| the finish card follows `canSave` | S4, S5 | `TrackingScreenStateTest`, `test_theFinishCard_followsCanFinish` |
| the Live Activity ends when the session ends by itself | S3 | `test_sessionFinishedByTheManager_endsTheLiveActivityOnce` |

## Re-plan trigger

Stop and ask the owner (the plan is changed only with approval, as a `chore(epic)` commit on the integration branch, which travels in the epic PR) when:

- S2 cannot keep an existing test green unchanged, in particular because making `stop()` idempotent breaks one;
- a subtask needs a file outside its `allowed_paths` (a Koin module, `KoinHelper`, a build file, `shared`, the Xcode project);
- a subtask's local review has a `[blocking]` finding after the review fix budget, or its gate stays red after the retry budget;
- the epic PR's CI or the CI reviewer finds something the local gate and local reviews did not, and it is not fixed within the usual budgets (two CI-fix rounds);
- the `feature-tracking` Kover floor (92) falls below its minimum after S4, since a floor is not lowered by a PR;
- `TrackingFinishTwiceUITests` fails on the epic branch after S2 or S5 and the cause is the interim state of the two platforms;
- the iOS Live Activity cannot be ended once per session without changing `TrackingLiveActivityController`'s contract beyond S3's paths;
- a human check of the epic-level Tier 2 shows the session does not end with the phone locked.

## Risks and what could change user-visible behavior

1. **The intended change (S2, visible when S2 is on the epic branch and reaches `main`):** on both platforms a session ends by itself at the end
   of the planned route also with the phone locked. The user may come back to a finished session they did not end, with no notice until the
   notification task (decision 5). The Android foreground notification disappears; the iOS Live Activity ends.
2. **The interim on the integration branch (S2 to S5), where only the local gate looks:** the iOS View's own detection can still fire once on a session the manager already ended. It calls
   `onStopClicked()`, which reads the same `Finished` state back; the Live Activity end is idempotent after S3, and the manager's `stop()` is
   idempotent after S2. `TrackingFinishTwiceUITests` must stay green on the epic branch; if it does not, that is a re-plan trigger.
3. **`stop()` inside the collector:** the manager's `stop()` cancels `locationObservationJob`, which is the coroutine that calls it. The fix that
   triggered it is already dispatched; an S2 test pins that the path ends with that fix and that the session stops once.
4. **Threads:** the tracker is created before the collector launches and touched only in it; a second `start()` or `restore()` replaces it before
   launching the next collector. No lock; an S2 test starts two sessions in a row.
5. **A resume at the end** completes at the first fix after the resume, not at the resume (section 2). Pinned by an S2 test.
6. **`stop()` becomes idempotent in `Idle` and `Finished`:** a caller that relied on a launcher stop there loses it. The code reading says none does
   (the Android and iOS screens stop only an active session); the gate on S2 runs every existing test to show it.
7. **Kover floors:** S4 deletes a covered Android class and its tests, so `feature-tracking` (floor 92) may fall; S2 adds `domain` coverage (floor 96, raised
   by the ratchet rule). Measure `:androidApp:feature-tracking:koverLog` before and after; if the module falls below its floor, stop and report.
8. **Restored sessions** (decision 4, unchanged): a restored session is `Paused`, a new tracker starts from index 0 and each fix moves progress by at
   most 10 route points, so on a long route completion is detected only after progress has caught up (the finding of section 1). The manager sees
   every fix, so it catches up as the user moves, and the plan does not change that.
9. **Process death while locked:** unchanged. The session is stored and comes back `Paused` (`TrackingSessionManager.restore`); no completion is
   evaluated while the process is gone.
10. **Local review base:** `scripts/local-review-prepare.sh` and the gate compare with the merge-base with `origin/main`. For the final review and gate on the
    integrated branch that is exactly right: the whole epic against `main`. For a subtask's local review it is too wide, because the branch holds the earlier
    subtasks: the draft description that is the review's `TASK` says that the scope is the commits `feature/epic/route-completion-to-domain..<subtask branch>` and lists the
    subtask's `allowed_paths`. A `--base` option for the script is a decision for the owner, recorded with the skill change that implements this flow, not here.
11. **No CI until the end (the owner's hypothesis, to be tested by this run):** the subtasks are merged on the local gate and local reviews alone; CI and the CI
    reviewer run once, on the epic PR. A failure that only CI shows (a different environment, a flake, the CI reviewer's reading of the whole diff) appears after
    every subtask is merged; the fix goes onto the same branch and is pushed to the open PR. The first run records the numbers that let the owner judge the
    decision (section "How this epic is run", "Evidence").

## Decisions of the owner (2026-11-19)

1. **Option B.** The detection of route completion runs in `TrackingSessionManager`, so a session ends at the end of the route even with the phone locked
   and the screen off, on both platforms, whatever the UI is doing. This is the intended new behavior on both platforms. The ViewModels and screens only
   show the result. (The first version of the plan recommended Option A, on the false premise in "Correction".)
2. **Drop `hasReachedDestination` from the finish-card condition: yes.** The card follows `canSave` (S4 on Android, S5 on iOS).
3. **Keep 25 m and "within the last 3 points": yes.** No threshold changes in this epic, including for the finding of section 1.
4. **Restored sessions keep starting progress from index 0:** not changed in this epic.
5. **Question 5, answered yes: the user gets a notification when a session ends by itself at the route's end.** It is not a subtask of this epic. It is its
   own task, recorded on the board as `session-ended-by-itself-notification`, and it starts after this epic is merged into `main`: it needs a design (a
   permission text on iOS, a channel on Android, what tapping it opens, one domain event both platforms use). The epic's S2 gives that task what it needs
   (the manager is the single place where the session ends by itself) and does not add the event.
6. **This runs as an epic by `epic-orchestration`:** an integration branch, a worker per subtask, one human merge into `main`; the order of the work comes from the
   `depends_on` of this plan, not from any instruction given at run time.
7. **The subtasks merge locally; there is one PR and one CI run (the owner's decision of 2026-11-19, and a hypothesis the first run tests):** a subtask is built by its
   worker, taken in by the orchestrator, reviewed and gated locally, and merged locally into the integration branch. There is no PR and no CI per subtask. When every
   subtask is merged, the integration branch is pushed once and the one PR `feature/epic/route-completion-to-domain` into `main` is opened; CI and the CI reviewer run on it, and the
   owner reviews it and merges it with a merge commit. The reasons the owner gave: the local merge and the local gate are much faster than GitHub's CI, so a CI run per
   subtask mostly buys waiting; one CI run on the final PR is enough and necessary; the owner is asked to merge or review one PR, not several. The ruleset for
   `feature/epic/*` is not used (it would refuse a fix pushed to the open epic PR after a red CI); the owner deletes it himself, and `main`'s own protection guards the epic PR.
   The owner will change his mind if the first run gives evidence that he is wrong, which is why the run records evidence.
8. **The Android foreground notification must not outlive the session (the owner's decision of 2026-11-20, found in the owner's Android tests of the epic PR):**
   the manager now ends a session at the route's end and stops the service at once, and the notification for the last `Tracking` state was posted on a worker
   thread after the service's `onDestroy` had cancelled it, so "Tracking...<distance>" stayed (3 of 3 owner runs; on the emulator 12 of 12 runs with the
   screen on and 11 of 12 locked before the fix). The fix may touch `data/src/androidMain` tracking code (`TrackingService`, the service scope in
   `AndroidCommonModule`) and its tests (`androidApp/app/src/test`), which no subtask owned: the service's scope runs on the main thread, and `onDestroy`
   removes the foreground notification with `stopForeground`. It changes no domain, iOS or Swift-visible API.
   **Refined the same day (the owner's decision of 2026-11-20):** the scope is not a Koin-provided one but `lifecycleScope` of a `LifecycleService`
   (`androidx.lifecycle:lifecycle-service`, the version ref of `lifecycle-runtime-ktx`, in `data`'s `androidMain` dependencies). It is the same
   main-immediate dispatcher, and the lifecycle itself cancels it in `super.onDestroy()`, so no `notify()` can run after `onDestroy`. The
   hand-made `newTrackingServiceScope()`, `trackingServiceScopeQualifier` and the Koin binding are removed.

## How this epic is run (the owner's decision of 2026-11-19)

- **Not to be run before the skill change.** This flow is implemented by the `epic-orchestration` change that makes the subtasks merge locally (the owner's decision of 2026-11-19). Until that change is merged, the skill on `main` still describes subtask PRs and a final board PR, which this plan contradicts: the owner's sentence "run the epic `route-completion-to-domain`" is not given before it is merged.
- **Locally, subtask by subtask.** For each subtask: a local branch from the integration branch, a worker (`implementer`) in a worktree, the orchestrator takes the commits
  in, runs the local `pr-reviewer` and the gate on the subtask branch, and merges it into `feature/epic/route-completion-to-domain` with a merge commit that names the subtask. A subtask whose
  review or gate does not pass within its budget stops the run with a report. Workers run in parallel only as far as the waves, the disjoint paths and the heavy-run lock allow.
- **One push, one PR.** When every subtask is merged and the board commit is made, the integration branch gets a local review and a full gate as a whole (the whole epic against
  `main`), is pushed once, and the one epic PR into `main` is opened. `ci.yml` has no push trigger for an epic branch (it would start a second run for the same commit), so the PR's runs are the only runs.
- **Board and `Status` travel in the epic PR.** The board commit (below) is the last commit of the integration branch.
- **If the epic PR's CI is red or the CI reviewer finds something:** fixes are commits on the same branch, reviewed and gated locally, and pushed to the open PR, within the usual
  retry budgets.
- **The owner's part:** delete the ruleset for `feature/epic/*`, merge this plan's PR, have the machine ready, do the human checks on the epic PR's head, review the PR and merge it with a merge commit.
- **Evidence (the part that tests the decision).** The run's final report has a "Drift found" part with a short measured comparison from real numbers: the wall time of each
  subtask's local review and local gate; the wall time of the one CI run on the epic PR (and of any re-run); anything that CI or the CI reviewer found that the local gate and
  local reviews had not, or the reverse; any flake. The owner judges the local-merge decision from it.

## Epic-level Tier 2

Automated, on the integrated branch before the PR is opened (the full local gate: the Android and iOS unit tests, the iOS package tests and both UI-test suites):

- The session ends at the route's end with no UI subscriber: `TrackingSessionManagerRouteCompletionTest` (domain, Android host and iOS simulator),
  `TrackingViewModelTest` `the session ends at the route's end while nobody collects the state` (Android), `test_reachingTheRouteEnd_finishesTheSessionWithoutAView` (iOS).
- The fixture walk reaches the end and "Finish" appears on iOS: `TrackingFinishTwiceUITests`, unchanged; the Android Compose and ViewModel tests of the finish card.
- The Live Activity ends once when the manager ends the session: `test_sessionFinishedByTheManager_endsTheLiveActivityOnce`.

Only the epic PR's CI and CI reviewer can show (and the run records whether they did): a difference between the CI environment and this machine (the runners, the pinned
simulator and Xcode, a clean checkout), a flake, the CI reviewer's reading of the whole diff, and the checks that run only there (the tooling job).

Human checks (what no test can observe: a locked screen and background location delivery), done by the owner on the epic PR's head (the branch is pushed with the PR), with the reason in
the epic PR:

- **Android** (emulator or device): plan a short closed route, Start, play a location route that ends at the route's end (the emulator's route playback), lock the
  screen before the end and wait for the playback to finish, unlock: the "Route completed" card shows, the foreground notification is gone, Finish saves one History entry.
- **iOS** (simulator with a simulated route, or a device): the same with the device locked (Cmd+L in the simulator): on unlock the card shows and the Live Activity has ended.
- **Final smoke check:** with the screen on, walk the same route on both platforms: the card appears at the end on both, Finish saves one History entry, and nothing else on
  the Tracking screen changed (Start, Pause, Resume and Stop behave as before).

## The epic's board commit (not a subtask)

The last commit of the integration branch, made by the orchestrator after every subtask is merged (`tm-pr-workflow`, "Board", rule 5), and part of the epic PR: it deletes the record
`route-completion-to-domain` and removes `After: route-completion-to-domain` from `tracking-ui-timer-independent-of-location` (one commit, `chore(board): remove route-completion-to-domain`);
it adds the records for the drift and the follow-ups the subtasks reported in the run record; it sets this plan's Status line to `done`.
The records `session-ended-by-itself-notification` and `finished-session-discard-control` already exist and stay.

## Definition of done

The epic is done when all of these hold on `main`:

- `grep -rn "isRouteCompleted\|lastProgressIndex\|routeCompletionThresholdMeters\|routeCompletionIndexMargin\|hasReachedDestination" iosApp/Packages/Tracking/Sources`
  prints nothing, and `TrackingView.swift` holds no route-completion state.
- `find androidApp -name RouteCompletionTracker.kt` prints nothing and `grep -rn "withRouteCompletion\|hasReachedDestination" androidApp --include='*.kt'`
  prints nothing; `RouteCompletionTracker` and its 19 `kotlin.test` cases are in `domain`.
- `TrackingSessionManager` ends a session at the end of the route with no UI subscriber, proved by the tests of the epic-level Tier 2.
- `RouteProgressTest` has the out-of-range cases and `calculateRouteProgress` throws for no input.
- Every subtask is merged locally into the integration branch and the board commit is its last commit; the integration branch had a local review and a full gate as a whole before its
  one push; the epic PR is open, its CI is green on the current head, and the owner has merged it (a merge commit, `epic-orchestration`, "Merging the epic into main").
- The run's report has the measured comparison of "How this epic is run" ("Evidence"), so the owner can judge the local-merge decision.
- The owner's human checks of the epic-level Tier 2 are done.
- `scripts/main-ui-run.sh --auto` is green after the merge.
- `BOARD.md` no longer has the record `route-completion-to-domain`, and `scripts/check-board.sh --base` passes.
