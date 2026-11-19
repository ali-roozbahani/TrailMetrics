# Epic: Route completion to `domain`, run by `TrackingSessionManager`

- **Slug:** route-completion-to-domain
- **Status:** approved by the owner on 2026-11-19 (answers 1 to 4 below, section 5). No code has changed yet; this
  document is the plan. Question 5 (section 5) is open and does not block PR 1 to PR 4. Rewritten on 2026-11-19 after the
  owner chose Option B for Question 1; the first version recommended Option A on a wrong premise (see "Correction").
- **Source:** BOARD.md record `route-completion-to-domain` (Order 60).
- **Integration branch:** none. A chain of ordinary PRs against `main`. `epic-orchestration`, "Epic or
  single task?", says an epic needs an integration branch only when `main` must not hold the half-built
  state. Every PR below leaves `main` working, and the PRs are strictly sequential up to PR 3, so waves and
  `allowed_paths` add nothing. PR 4 and PR 5 are independent of each other (one platform each); the queue builds
  one entry at a time, so they run one after the other. Each PR is an entry of the local queue.
- **Goal:** the route counts as completed in one place, `domain`, and `TrackingSessionManager` runs the detection,
  so a session ends at the end of the planned route on both platforms whatever the UI is doing: also with the phone
  locked and the screen off. The ViewModels and screens only show the result: `TrackingView.swift` renders only, and
  Android's `withRouteCompletion` and `RouteCompletionTracker` are gone. `calculateRouteProgress` does not throw for an
  out-of-range input.
- **Out of scope:** the thresholds (25 m, last 3 points: decision 3); progress of a restored session (it starts from
  index 0 again: decision 4); persisting progress across process death; the map drawing; telling the user that a session
  ended while the phone was locked (Question 5).
- **Approved by:** the owner, 2026-11-19, with the four answers of section 5 (recorded here from the owner's decisions
  given for this update). The owner still merges this PR (`/docs/epics/` is a protected path).

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
what the owner's decision 1 changes on both platforms on purpose (PR 3).

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
   `routeProgress: StateFlow<RouteProgress?>` (null before the first fix and with no plan). The constructor and the Koin graph do not
   change: the tracker is built inside. A new session after `discard()` gets a new tracker.

   Evaluated at each fix and nowhere else: a resume at the route's end completes at the first fix after the resume, not at the
   resume itself (the old Android rule evaluated at the next state emission). The tracker is touched only inside the collector
   coroutine (`observeLocation` cancels the previous one first), so it needs no lock.

**Stays in the platforms:**

- What the UI does with the result: Android's `TrackingViewModel` puts `routeProgress` into `TrackingScreenState`; iOS's
  `TrackingViewModel` publishes it. The finish card follows `canSave` (decision 2: `hasReachedDestination` is removed from the
  card's condition and from the state).
- The iOS Live Activity: it ends when the observed state turns `Finished`, whoever caused it (PR 2). Android's equivalent is the
  foreground service, which the manager's `stop()` already stops through `TrackingServiceLauncher`.
- Drawing the traveled segment, the camera, the card.

**Why Option B:** the decision "the session is at the end of its route" is a rule about the session, not about a screen; the
manager already holds the plan and sees every fix, and it keeps running when the UI does not (the Android foreground service, iOS
background location). Option A would have kept the rule in the UI layer, where the two platforms stop at different moments (the
Correction). `tm-kmp-shared`, "Where logic lives": derived state and rules both platforms need are in `domain`, tested once, and
ViewModels only adapt.

## 3. The PRs, in order

Branches use the three allowed prefixes. Every PR runs the gate in full. Dependencies: PR 1 and PR 2 are independent; PR 3 needs
PR 1; PR 4 needs PR 2 and PR 3; PR 5 needs PR 4; PR 6 needs PR 5. The queue builds one at a time.

### PR 1: `calculateRouteProgress` does not throw for an out-of-range input

- Branch: `bugfix/route-progress-out-of-range-index`. Touches: `domain` only.
- Change: the guard of section 2.1, KDoc updated.
- Proof: red test first (`tm-testing`, "Bugfixes: red test first") in `RouteProgressTest`: `previousIndex` equal to and above
  `plannedRoute.size`, `previousIndex = -1`, `searchWindow = -5`, a one-point route with `previousIndex = 3`; each fails today with an
  exception and passes after; a valid-input case asserts the result is unchanged.
- Must stay green unchanged: the 5 existing `RouteProgressTest` cases, the 19 `RouteCompletionTrackerTest` cases (still on Android),
  `TrackingViewModelTest`, the iOS-side `UiTestFakesTest` (it calls the function).
- Leaves working: both platforms, identical behavior.

### PR 2: the iOS Live Activity ends whenever the observed state turns `Finished`

- Branch: `chore/ios-live-activity-ends-on-finished`. Touches: `iosApp/Packages/Tracking`.
- Why first: today the only way to `Finished` on iOS is the ViewModel's own `onStopClicked()`, which ends the Live Activity. After
  PR 4 the manager ends the session, so the ViewModel has to end the Live Activity when it sees `Finished`. Doing it before keeps
  every PR working. The end must happen once per session even though `onStopClicked()` also ends it.
- Proof: XCTest in `TrackingViewModelLiveActivityTests` on the real ViewModel over `TestSupport` fakes: a session driven to `Finished`
  through the manager (`trackingSessionManager.stop()`, not the ViewModel) ends the Live Activity once; Stop through the ViewModel
  ends it once. Written first and red for the first case.
- Must stay green unchanged: every existing `TrackingViewModelLiveActivityTests` and `TrackingLiveActivityControllerTests` case.
- Leaves working: iOS unchanged for the user.

### PR 3: the domain `RouteCompletionTracker`, owned by `TrackingSessionManager`, exposing `routeProgress` (no auto-stop yet)

- Branch: `feature/session-route-progress-in-manager`. Depends on: PR 1. Touches: `domain` (and its README).
- Change: the tracker class and the manager's ownership and `routeProgress` flow of section 2, without the call to `stop()`. The tracker is
  used (progress), so no dead code. Android and iOS do not read `routeProgress` yet.
- Proof (`domain` commonTest, `kotlin.test`, the existing fakes): `RouteCompletionTrackerTest` with the 19 cases of Android's file, same
  names, moved and adapted to `update`/`RouteCompletionUpdate`; `TrackingSessionManagerTest` new cases: progress advances with each fix
  while nothing collects any flow; no progress without a plan; a new session gets a fresh tracker; a restored session starts from index
  0 (decision 4, pinned).
- Must stay green unchanged: all existing `TrackingSessionManagerTest` and `UpdateTrackingStateUseCaseTest` cases, and everything on
  Android and iOS (they do not use the new flow). Android's own tracker and its tests stay in this PR.
- Leaves working: both platforms, identical behavior. Raises the `domain` Kover floor by the ratchet rule.

### PR 4: the session ends by itself at the route's end, on both platforms (the intended behavior change); Android shows the result

- Branch: `feature/session-ends-at-route-end`. Depends on: PR 2 and PR 3. Touches: `domain`, `androidApp/feature-tracking`.
- Change: the manager calls its `stop()` on `reachedNow`. Android: `TrackingViewModel` reads `routeProgress` from the manager; the
  internal `RouteCompletionTracker`, `RouteCompletionTrackerTest`, `withRouteCompletion` and `hasReachedDestination` are deleted
  (decision 2: the card follows `canSave`).
- Proof: `domain`: with no collector of any flow, fixes along the plan end with `currentState` `Finished`, `routeProgress` at the end, the
  launcher stopped once, the stored session kept; not at the end of a plan that is empty; not while paused; stops once, not at each
  later fix; stopped by the manager from inside its own collector without losing the fix (the session path ends with that fix). Android
  `TrackingViewModelTest`: the manager is driven to the route's end **while nobody collects the ViewModel's state** (the locked screen),
  then the state is collected: it is `Finished`, `canSave` is true, the progress is at the end. These are the proofs that the end of
  the session does not depend on any UI subscriber.
- Existing tests that change, and only these: the three assertions of `TrackingViewModelTest` on `hasReachedDestination` (they assert
  `Finished` and `canSave` instead) and the construction of `TrackingScreenState` with `hasReachedDestination` in
  `TrackingScreenStateTest`. Every other case of both files, `TrackingFinishTwiceUITests` and the Compose tests stay green unchanged.
- iOS in this PR: untouched. Its View still runs its own detection, which now rarely fires because the manager has already
  stopped the session (it needs the `.tracking` state); when it does, its `onStopClicked()` is harmless: same final state, and the
  Live Activity end is idempotent (PR 2). The behavior change reaches iOS through the shared manager.
- **Human check, the one of the epic (Tier 2, what no test can observe: a locked screen and background location delivery):**
  - Android (emulator or device): plan a short closed route, Start, play a location route that ends at the route's end (the emulator's
    route playback), lock the screen before the end and wait for the playback to finish, unlock: the "Route completed" card shows,
    the foreground notification is gone, Finish saves one History entry.
  - iOS (simulator with a simulated route, or a device): the same with the device locked (Cmd+L in the simulator): on unlock the card
    shows and the Live Activity has ended.
- Leaves working: both platforms end the session at the end of the route; Android's own copy of the rule is deleted; iOS still has its
  own redundant View code until PR 5.

### PR 5: iOS `TrackingView` renders only

- Branch: `chore/ios-route-completion-in-viewmodel`. Depends on: PR 4. Touches: `iosApp/Packages/Tracking`.
- Change: `TrackingViewModel` publishes `routeProgress` from the manager's flow (observed with `for await` like the state, and
  cancelled with it); `TrackingView` loses `routeProgress`, `lastProgressIndex`, `hasReachedDestination`, the two constants,
  `isRouteCompleted`, `updateRouteProgress` and both `onChange` blocks; the card follows `canFinish`.
- Proof: XCTests on the real ViewModel over `TestSupport` fakes, as `TrackingViewModelTests` does: progress follows the fixes; reaching
  the end ends the session (state `Finished`, `canFinish`, launcher stop count 1, Live Activity ended once) with no View involved;
  not while paused; an empty plan never completes. Written first; they do not compile before the change (the red evidence is the
  missing member, said plainly).
- Must stay green unchanged: `TrackingFinishTwiceUITests`, all of `TrackingViewModelTests`, `SavedSessionOfferTests`,
  `TrackingViewModelClearSessionTests`, `TrackingViewModelFinishTests`, the Live Activity tests of PR 2.
- Leaves working: both platforms use the manager's rule; D1 and D6 are gone.

### PR 6: documentation sweep and closing the record

- Branch: `chore/route-completion-docs-and-board`. Depends on: PR 5. Touches: docs, skills, `BOARD.md`.
- Change: `tm-android` SKILL.md, section "Compose", the bullet on route progress and completion (it names `RouteCompletionTracker` as
  Android's); `domain/README.md` (the `tracking/` entry); this plan's Status line. `BOARD.md`: delete the record
  `route-completion-to-domain` in its own commit `chore(board): remove route-completion-to-domain`, and remove
  `After: route-completion-to-domain` from `tracking-ui-timer-independent-of-location` in the same commit. Each earlier PR sweeps the
  names it makes stale ("Docs follow the code you changed"); this PR is what is left, and may be only the board commit.
- Proof: `scripts/check-board.sh` and `scripts/check-board.sh --base` pass; the greps of section 6 return nothing.

## 4. Risks and what could change user-visible behavior

1. **The intended change (PR 4):** on both platforms a session now ends by itself at the end of the planned route also with the phone
   locked. The user may come back to a finished session they did not end, with no notice (Question 5). The Android foreground
   notification disappears; the iOS Live Activity ends.
2. **The interim in iOS (PR 4 to PR 5):** the View's own detection can still fire once on a session the manager already ended. It calls
   `onStopClicked()`, which reads the same `Finished` state back and ends the Live Activity (idempotent after PR 2). The existing UI test
   `TrackingFinishTwiceUITests` must stay green; if it does not, PR 5 is merged into PR 4 and the plan says so.
3. **`stop()` inside the collector:** the manager's `stop()` cancels `locationObservationJob`, which is the coroutine that calls it. The fix
   that triggered it is already dispatched; the PR 4 test pins that the path ends with that fix and that the session stops once.
4. **Threads:** the tracker is created before the collector launches and touched only in it; a second `start()` or `restore()` replaces it
   before launching the next collector. No lock; a test starts two sessions in a row.
5. **A resume at the end** completes at the first fix after the resume, not at the resume (section 2). Pinned by a test.
6. **Kover floors:** PR 4 deletes a covered Android class and its tests, so `feature-tracking` (floor 92) may fall; PR 3 and PR 4 add
   `domain` coverage (floor 96, raised by the ratchet rule). Measure `:androidApp:feature-tracking:koverLog` before and after; if the
   module falls below its floor, stop and report: a floor is not lowered by a PR (`scripts/check-kover-floors.sh`).
7. **Restored sessions** (decision 4, unchanged): a restored session is `Paused`, a new tracker starts from index 0 and each fix moves
   progress by at most 10 route points, so a restored session on a long route completes only after progress has caught up (the finding
   of section 1). The manager sees every fix, so it catches up as the user moves, and the plan does not change that.
8. **Process death while locked:** unchanged. The session is stored and comes back `Paused` (the manager's `restore`); no completion is
   evaluated while the process is gone.
9. **Existing tests that change:** only those named in PR 3 (`RouteCompletionTrackerTest` moves) and PR 4 (the `hasReachedDestination`
   assertions and one state construction).

## 5. Decisions of the owner (2026-11-19) and the open question

1. **Where does completion run? Option B.** In `TrackingSessionManager`, so a session ends at the end of the route even with the phone
   locked and the screen off, on both platforms, whatever the UI is doing. This is the intended new behavior on both platforms.
   The ViewModels and screens only show the result. (The first version recommended Option A, on the false premise in "Correction".)
2. **Drop `hasReachedDestination` from the finish-card condition: yes.** The card follows `canSave` (PR 4 on Android, PR 5 on iOS).
3. **Keep 25 m and "within the last 3 points": yes.** No threshold changes in this epic, including for the finding of section 1.
4. **Restored sessions keep starting progress from index 0:** not changed in this epic.

**Question 5 (open, does not block PR 1 to PR 4): tell the user that a session ended by itself while the phone was locked?** After
PR 4 the user can unlock to a finished session with no sign of when or why. **Recommendation: no new notification in this epic.** The iOS Live
Activity shows the ended state and the Android foreground notification disappears; a notification needs its own permission text on iOS and
its own design on both. If the owner wants it, it is a task of its own after PR 4; ask before PR 4 is merged so the human check can include it.

## 6. Definition of done

The epic is done when all of these hold on `main`:

- `grep -rn "isRouteCompleted\|lastProgressIndex\|routeCompletionThresholdMeters\|routeCompletionIndexMargin\|hasReachedDestination" iosApp/Packages/Tracking/Sources`
  prints nothing, and `TrackingView.swift` holds no route-completion state.
- `find androidApp -name RouteCompletionTracker.kt` prints nothing and `grep -rn "withRouteCompletion\|hasReachedDestination" androidApp --include='*.kt'`
  prints nothing; `RouteCompletionTracker` and its 19 `kotlin.test` cases are in `domain`.
- `TrackingSessionManager` ends a session at the end of the route with no UI subscriber, proved by a `domain` test and by the Android
  ViewModel test of PR 4; the iOS ViewModel tests of PR 5 prove the iOS side.
- `RouteProgressTest` has the out-of-range cases and `calculateRouteProgress` throws for no input.
- The gate and CI are green on every PR, and `scripts/main-ui-run.sh --auto` is green after the last merge.
- The locked-screen human check of PR 4 is done on both platforms, and Question 5 is answered or recorded as a task of its own.
- `BOARD.md` no longer has the record `route-completion-to-domain`: PR 6 deletes it in its own commit
  (`chore(board): remove route-completion-to-domain`) and removes it from the `After:` line of `tracking-ui-timer-independent-of-location` in
  the same commit; `scripts/check-board.sh --base` passes.
