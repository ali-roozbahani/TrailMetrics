# Epic: Route completion to `domain`

- **Slug:** route-completion-to-domain
- **Status:** plan for review, written 2026-11-19. No code has changed. The owner's answers to
  "Questions for the owner" (below) are needed before PR 3 and PR 4; PR 1 and PR 2 do not depend on them.
- **Source:** BOARD.md record `route-completion-to-domain` (Order 60).
- **Integration branch:** none. A chain of ordinary PRs against `main`. `epic-orchestration`, "Epic or
  single task?", says an epic needs an integration branch only when `main` must not hold the half-built
  state. Here every PR leaves `main` working and the app behaving as before (PR 3 and the questions
  aside, see "Risks"), and the PRs are strictly sequential (each needs the one before), so waves and
  `allowed_paths` add nothing. Each PR is an entry of the local queue.
- **Goal:** the rule "the route is completed" and the progress along the planned route are written once,
  in `domain`, with `kotlin.test` coverage. Android's `TrackingViewModel` and iOS's `TrackingViewModel` call
  it. `TrackingView.swift` only renders. `calculateRouteProgress` does not throw for an out-of-range input.
- **Out of scope:** where in the app the auto-stop runs (a session-level auto-stop in
  `TrackingSessionManager` is Question 1, not part of this epic); the thresholds (25 m, last 3 points);
  persisting progress across process death; the Live Activity; the map drawing; the control rules
  (PR #358, a separate task).
- **Approved by:** pending (owner), not approved yet.

## 1. What the code does today

Facts below are read from `main` at 3c93063c. PR #358 (the tracking control rules, open when this plan was written) changes
two lines the plan names: the finish card condition reads `state.canSave` instead of `state.trackingState is TrackingState.Finished`
on Android, and iOS's `canFinish` is `canSave && !isDiscarding`. Where this plan says `Finished`, it holds either way.

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

`TrackingViewModel.withRouteCompletion` (`TrackingViewModel.kt:151`) calls it inside
`combine(...).map(::withRouteCompletion).stateIn(viewModelScope, WhileSubscribed(5_000))`, with
`state.currentPath.lastOrNull()` (the path of `Tracking`, `Paused` and `Finished`), and on true calls
`trackingSessionManager.stop()`. It copies `routeProgress` and `hasReachedDestination` into
`TrackingScreenState`. The screen shows the finish card when
`state.hasReachedDestination || state.trackingState is TrackingState.Finished` (`TrackingScreen.kt`, the `AnimatedContent` target).

Tests: `RouteCompletionTrackerTest` (19 cases: thresholds pinned, empty route, no progress before a
location, progress never backwards, same location twice, stops exactly once, third-to-last point,
a point before the last three, past the end inside and outside the threshold, the start of a closed
loop, paused at the end, idle and finished, exactly at and just beyond 25 m) and three in
`TrackingViewModelTest` (four: "route progress follows location updates", "reaching the end of the planned route
stops tracking and keeps the progress", "reaching the end again in a later session does not stop a second
time", plus "a session stopped at the route end can be finished and saved").

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
`UiTestFakesTest.kt:220` (the fixture walk ends inside the radius).

### Differences between the platforms

| # | Aspect | Android | iOS | Effect today |
|---|---|---|---|---|
| D1 | Where the decision lives | `RouteCompletionTracker` in `feature-tracking`, owned by the ViewModel | the View (`TrackingView`), 3 `@State` values and 2 duplicated constants | iOS is untestable; the rule can drift (it has not yet: both use 25.0 and 3) |
| D2 | What triggers it | every emission of the combined state while the screen is subscribed (plus the 5 s grace of `WhileSubscribed`); `stop()` is called as a side effect inside a flow `map` | SwiftUI `onChange` of `currentPath` and of `isRouteCompleted`, so only while the view is in the hierarchy | with the screen locked or the app in the background the two can behave differently. No test shows how. See Question 1 |
| D3 | Which path feeds the location | `currentPath` of `Tracking`, `Paused` and `Finished` | `currentPath` of `Tracking` and `Paused` only (`Finished` gives `[]`) | none visible: a `Finished` session produces no new location, and both keep the last progress |
| D4 | What "stop" does at the end | `trackingSessionManager.stop()` | `viewModel.onStopClicked()`: cancels the observation tasks, reads the state back, ends the Live Activity | platform part (Live Activity). Stays on iOS |
| D5 | Lifetime of the latch and the index | the ViewModel (survives rotation) | the view's `@State` (one view per screen) | none: one screen, one session |
| D6 | `searchWindow` | the default (10) | an explicit 10 | the same value, written twice |
| D7 | Index type | `Int` | `Int32` | none |
| D8 | Test coverage | 19 + 4 cases | 0 unit cases, 1 UI test | iOS completion is unprotected |

No difference changes what the user sees today in a normal walk. That is why the plan can move the code without a
product decision, and why PR 3 (iOS) is the only PR whose behavior is not provably identical (D2): see "Risks".

## 2. Target design

**Moves to `domain`:**

1. `calculateRouteProgress` gets a guard: `previousIndex` is clamped to `0..plannedRoute.lastIndex`, a negative
   `searchWindow` counts as 0. It returns the same values for every input that is valid today.
2. A new class `dev.roozbahani.trailmetrics.domain.tracking.RouteCompletionTracker(plannedRoute: List<Coordinates>)`,
   ported from Android line by line, public, with the two constants private to it. One instance per
   session screen. It is stateful (index, last location, latch) and not thread-safe; both platforms call it from
   one thread (Android: the ViewModel's pipeline on `Main`; iOS: the `@MainActor` ViewModel), and the KDoc says so.

   ```kotlin
   class RouteCompletionTracker(plannedRoute: List<Coordinates>) {
       fun update(currentLocation: Coordinates?, state: TrackingState): RouteCompletionUpdate
   }
   data class RouteCompletionUpdate(
       val progress: RouteProgress?,
       val hasReachedDestination: Boolean,
       val reachedNow: Boolean   // true exactly once
   )
   ```

   A single return value (not three properties plus a boolean) so the Swift side reads one immutable
   result and SKIE exports a plain class and a data class. It is built directly by each ViewModel, as
   `TrackingViewModel` already builds its other per-screen values: no Koin binding and no `KoinHelper`
   getter (a per-screen object that takes the planned route is not a singleton).

**Stays in the platforms:**

- What happens on `reachedNow`: Android calls `trackingSessionManager.stop()`; iOS calls `onStopClicked()`
  (it also ends the Live Activity, D4). It is a platform effect, not a rule.
- Publishing the result: Android copies it into `TrackingScreenState`; iOS into two `@Published` values on
  `TrackingViewModel`.
- Drawing (`traveledSegment` on the map) and the finish card.

**Why this split:** the decision ("is the route done") is a pure function of location, state and plan, so it is
tested once. The reaction is the part that differs by platform (Live Activity), and the owner's rule in
`tm-kmp-shared`, "Where logic lives", is that ViewModels adapt shared logic and own no rule. A stateful class
and not a `TrackingMetricsUseCase`-style function because the index and the latch are per session.

**Why not in `TrackingSessionManager`:** the manager already holds `plannedRoute` in `SessionDetails`, so an
auto-stop there is possible and would work with the screen off. It would change when a session ends (D2), which
is a product decision (Question 1), so it is not part of this epic.

## 3. The PRs, in order

Branches use the three allowed prefixes. Every PR runs the gate in full: each touches `domain` or the apps, so
`scripts/classify-changes.sh --ui-scope` includes the UI tests of the platform it touches (domain: both).

### PR 1: `calculateRouteProgress` does not throw for an out-of-range input

- Branch: `bugfix/route-progress-out-of-range-index`. Depends on: nothing. Touches: `domain` only.
- Change: the guard of section 2.1. Update the KDoc.
- Proof: red test first (`tm-testing`, "Bugfixes: red test first") in `RouteProgressTest`: `previousIndex` equal to
  and above `plannedRoute.size`, `previousIndex = -1`, `searchWindow = -5`, a one-point route with
  `previousIndex = 3`; each fails today with `IllegalArgumentException` or `IndexOutOfBoundsException` and returns the
  clamped result after. A valid-input case asserts the result is unchanged.
- Must stay green unchanged: the 5 existing `RouteProgressTest` cases, the 19 `RouteCompletionTrackerTest` cases,
  `TrackingViewModelTest`, `UiTestFakesTest` (line 220 calls it).
- Leaves working: both platforms, identical behavior. Raises the `domain` Kover floor if coverage rises
  ("Coverage ratchet").

### PR 2: the domain `RouteCompletionTracker`, and Android uses it

- Branch: `chore/route-completion-tracker-in-domain`. Depends on: PR 1. Touches: `domain`, `androidApp/feature-tracking`.
- Change: add the class and `RouteCompletionUpdate` (section 2). Delete
  `feature-tracking/.../RouteCompletionTracker.kt`. `TrackingViewModel.withRouteCompletion` builds the domain
  tracker and calls `update(...)`; on `reachedNow` it calls `trackingSessionManager.stop()` as now. The class is used in
  the same PR, so no dead code ("No dead code").
- Proof: `RouteCompletionTrackerTest` is moved to `domain/src/commonTest/.../tracking/` and keeps its 19 cases and
  names; its assertions change only from `onUpdate(...)`/`tracker.progress` to the `RouteCompletionUpdate`
  fields. This is the one set of existing tests that is edited, mechanically, and the PR description says so.
  Add: a case that `update` after the latch returns `reachedNow = false` with `hasReachedDestination = true`,
  and one that the two constants are pinned (the existing "keeps its current thresholds" case, now reading the
  behavior at 25.0 m and the margin 3, since the constants are private).
- Must stay green unchanged: every `TrackingViewModelTest` case (the 4 completion ones included),
  `TrackingScreenStateTest`, the Compose tests of `feature-tracking`.
- Leaves working: Android unchanged for the user; iOS untouched (still its own View code).
- Risk specific to this PR: the `feature-tracking` Kover floor is 92 and a fully covered class leaves that
  module. Measure `:androidApp:feature-tracking:koverLog` before and after; if the module falls below its floor,
  stop and report (a floor is not lowered by a PR; `scripts/check-kover-floors.sh`).

### PR 3: iOS `TrackingViewModel` owns progress and completion; `TrackingView` only renders

- Branch: `chore/ios-route-completion-in-viewmodel`. Depends on: PR 2, and on the owner's answer to Question 1
  (D2 changes here). Touches: `iosApp/Packages/Tracking`.
- Change: `TrackingViewModel` builds `RouteCompletionTracker(plannedRoute: plannedRoutePoints)`; in
  `observeTrackingState()` it calls `update(currentLocation:state:)` with the last point of `recordedPath`
  after each emitted state, publishes `routeProgress` and `hasReachedDestination` (`public private(set)`), and
  on `reachedNow` calls its stop path. `TrackingView` loses `routeProgress`, `lastProgressIndex`,
  `hasReachedDestination`, the two constants, `isRouteCompleted`, `updateRouteProgress` and both
  `onChange` blocks, and reads the two published values.
  Careful point: `onStopClicked()` cancels `stateObservationTask`, the task that would be calling it. The stop must
  run after the loop body, or the stop path must not cancel its caller; decided in the PR and tested.
- Proof: XCTests on the real `TrackingViewModel` over `TestSupport` fakes (as `TrackingViewModelTests` does),
  written first and red against the View-only code (they do not compile against it, so the red evidence is the
  missing members, said plainly): progress follows locations; reaching the end while tracking stops once, state
  `Finished`, `hasReachedDestination` true, `serviceLauncher.stopCount == 1`; paused at the end does not stop until
  resume; idle and finished do not stop; empty plan never completes; an adapter test that the published values
  equal `RouteCompletionTracker` run on the same inputs.
- Must stay green unchanged: `TrackingFinishTwiceUITests` (the completion card appears after the walk),
  all of `TrackingViewModelTests`, `SavedSessionOfferTests`, `TrackingViewModelClearSessionTests`.
- Leaves working: iOS completes at the route end through the shared rule; D1 and D6 are gone.

### PR 4 (only if Question 2 is answered yes): the finish card shows on `canSave`, not on `hasReachedDestination`

- Branch: `chore/finish-card-follows-state`. Depends on: PR 3 and PR #358 (`TrackingControls.canSave`, once merged). Touches: `TrackingScreen.kt`, `TrackingView.swift`, and `RouteCompletionUpdate`/the state classes lose
  `hasReachedDestination`.
- Proof: the existing screen and ViewModel tests are updated where they assert `hasReachedDestination`
  (three in `TrackingViewModelTest`, `TrackingScreenStateTest`) and a test that the card shows exactly when `canSave`.
- If the answer is no, this PR does not exist and the epic is done after PR 5.

### PR 5: documentation sweep and closing the record

- Branch: `chore/route-completion-docs-and-board`. Depends on: the last code PR. Touches: docs, skills, `BOARD.md`.
- Change: `tm-android` SKILL.md lines 113 to 116 (the `RouteCompletionTracker` mention is on line 115) (they name `RouteCompletionTracker` as Android's);
  `domain/README.md` (the `tracking/` line); the plan's Status line; `BOARD.md`: delete the record
  `route-completion-to-domain` in its own commit `chore(board): remove route-completion-to-domain`, and remove
  `After: route-completion-to-domain` from `tracking-ui-timer-independent-of-location`.
  Each earlier PR already sweeps the names it makes stale ("Docs follow the code you changed"); this PR is
  only what is left, and may be empty of skill changes, in which case it is only the board commit.
- Proof: `scripts/check-board.sh` and `scripts/check-board.sh --base` pass; the greps in "Definition of done" return nothing.

PR 1 and PR 2 can be built before the owner answers. The queue builds one entry at a time, so PR 3 waits for the answer.

## 4. Risks and what could change user-visible behavior

1. **iOS trigger moves (D2).** Today iOS decides in SwiftUI `onChange`; after PR 3 it decides when the ViewModel's
   state observation delivers a state, as Android does. With the screen locked and the app in the background
   (location background mode on), the ViewModel's observation keeps running; the View's `onChange` may not.
   After PR 3 the session can therefore auto-stop at the route end while the phone is locked, which today it may not.
   No automated test can show background behavior; this is the one human check of the epic (Tier 2, "what
   automated tests cannot show"), written into PR 3: walk or simulate a route in the simulator, lock the device,
   see the session finished when unlocking. Question 1 asks the owner whether this is wanted.
2. **A task cancelling itself on iOS** (PR 3, above): `onStopClicked()` cancels `stateObservationTask`. Known and
   documented in `tm-ios`; the PR must not make the stop path skip `liveActivityController.end`.
3. **A stateful Kotlin object in Swift.** Not thread-safe; the iOS ViewModel is `@MainActor`, the KDoc says one
   thread. Swift receives `RouteCompletionUpdate.progress` as an optional; `lastIndex` is `Int32` in Swift.
4. **A floor that drops** (PR 2): see its risk note. A moved class takes its coverage with it.
5. **Restored sessions** (not a regression, the same on both platforms): a restored session is always `Paused`
   (`TrackingSessionManager.restore`), a new tracker starts at index 0, and each later location moves progress by
   at most 10 points, so the traveled segment can lag for a few updates after resume and completion is detected
   only after progress has caught up. Left as it is (Question 4).
6. **Tests that change.** Only `RouteCompletionTrackerTest` (moved and adapted to the new return type, PR 2) and, if
   Question 2 is yes, the `hasReachedDestination` assertions (PR 4). Nothing else existing is edited.

## 5. Questions for the owner

1. **Where does completion run: only while the screen observes, or in the session itself?**
   Today both platforms decide in the UI layer, with different "while observed" rules (D2). Option A: keep it
   UI-layer in `domain`'s tracker (this plan); iOS then follows Android, including auto-stop with a locked screen
   (Risk 1). Option B: put it in `TrackingSessionManager` so it ends the session whatever the UI does (a larger
   change, a new behavior on both platforms, its own plan).
   **Recommendation: A in this epic**, with B recorded as a separate task if you want it. A keeps Android as it is
   and brings iOS to the same behavior (the Android behavior is the reference, as in the control-rules task).
   Confirm that iOS auto-stopping with a locked screen is wanted.
2. **Drop `hasReachedDestination` from the finish-card condition?** Both screens show the card when
   `hasReachedDestination || state is Finished`. The only way to `Finished` is the completion stop (Stop discards)
   or a restored finished session, so `Finished` already implies the card, and the latch only covers the instant
   between setting it and the state arriving. **Recommendation: yes** (PR 4): one rule instead of two. If no, the
   latch stays in the update and PR 4 does not exist.
3. **Keep 25 m and "within the last 3 points"?** Identical on both platforms and pinned by a test.
   **Recommendation: keep.** Say so if you want a different value; it is then a one-line change in the domain
   class and its tests, and not part of this epic's structure.
4. **Restored sessions: start progress from index 0 or from the stored path?** Same on both platforms today.
   **Recommendation: leave it** (Risk 5); a fix needs the progress persisted or recomputed from the whole path, which
   is a separate task.

## 6. Definition of done

The epic is done when all of these hold on `main`:

- `grep -rn "isRouteCompleted\|lastProgressIndex\|routeCompletionThresholdMeters\|routeCompletionIndexMargin" iosApp/Packages/Tracking/Sources`
  prints nothing, and `TrackingView.swift` holds no route-completion state.
- `find androidApp -name RouteCompletionTracker.kt` prints nothing; the class and its 19 `kotlin.test` cases
  are in `domain`.
- `RouteProgressTest` has the out-of-range cases and `calculateRouteProgress` throws for no input.
- `TrackingViewModel` on each platform calls the domain tracker and has an `onAction`/XCTest case for completion
  (Android 4 existing cases, iOS the new ones of PR 3).
- The gate and CI are green on every PR; `scripts/main-ui-run.sh --auto` is green after the last merge.
- The owner has answered Questions 1 to 4 in the plan's text (the "Approved by" line names them and the date), and
  the one human check of PR 3 is done.
- `BOARD.md` no longer has the record `route-completion-to-domain`: PR 5 deletes it in its own commit
  (`chore(board): remove route-completion-to-domain`) and removes it from the `After:` line of
  `tracking-ui-timer-independent-of-location` in the same commit; `scripts/check-board.sh --base` passes.
