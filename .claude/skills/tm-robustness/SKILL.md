---
name: tm-robustness
description: Use for any Kotlin or Swift change in TrailMetrics, with the area skill (tm-android, tm-ios, tm-kmp-shared) — rules that keep the app from crashing, hanging (ANR), losing data or leaking. Covers crashes and ANR, exceptions, dispatchers and threads, process death and lifecycle, memory and leaks, performance and efficiency, each with its enforcement and review severity. Not for module structure (see the Architecture sections of tm-android, tm-ios, tm-kmp-shared) or test code (see tm-testing).
---

# TrailMetrics robustness

Every rule has an id (`C1`, `E1`, ...) that a review finding cites. A rule is one imperative line,
the reason, where the repo already does it (`Example`, or `no example yet`), what enforces it
(`Enforced`) and the highest severity a violation can have in review (`Severity`):

- `blocking`: a violation the reviewer verifies in the files (crash or ANR path, data loss, a
  blocking call on the main thread, a swallowed or unhandled exception, a missing unregister, a
  hard-coded dispatcher in a class, a dependency-rule violation).
- `important`: judgement or suspicion the files cannot prove (performance, SOLID smells, a
  process-death gap that looks likely, a leak risk).

No rule here is a `note`. `Android` and `iOS` mark a rule for one platform; the rest apply to
Kotlin and Swift alike. `reviewer only` means no tool checks it. The detekt rule names are those
of detekt 1.23.8; "plain" detekt is the gate's `detekt` task, which has no type resolution, so a
rule that needs it never fires there (see "Mechanical rules").

## Crashes and ANR

- **C1** No blocking call (file, database, network, `runBlocking`, `Thread.sleep`, heavy
  computation) on the main thread or in a lifecycle callback (`onCreate`, `onReceive`,
  `onStartCommand`, `body`, `init`). Why: the main thread drives input and drawing; 5 s blocked is
  an ANR. Example: `ActivityHistoryRepositoryImpl` (`withContext(ioDispatcher)`). Enforced:
  reviewer only (`runBlocking` and `Thread.sleep` have no rule; detekt `SleepInsteadOfDelay`
  needs type resolution). Severity: blocking.
- **C2** Never `!!`, read a `lateinit` before it is set, or use an unchecked cast or an index on
  external data (network, disk, intent extras, nav arguments); use `checkNotNull(x) { "why" }`,
  `as?`, `getOrNull`. Why: each throws on input you do not control. Example: no `!!` and no
  `lateinit` in production Kotlin. Enforced: detekt `UnsafeCallOnNullableType` (on by default),
  `UnsafeCast` (type resolution, plain detekt skips it); `lateinit` and index access reviewer only
  (`LateinitUsage` is off). Severity: blocking.
- **C3** Swift: never a force unwrap `!`, `try!` or `as!` on external data. Why: each traps and
  kills the process. Example: none in production Swift. Enforced: SwiftLint `force_unwrapping`,
  `force_try`, `force_cast` (all errors). Severity: blocking.
- **C4** An exception thrown by Kotlin that Swift calls follows the `@Throws` policy in
  `tm-kmp-shared` ("`@Throws` policy"); do not restate it there or here. Why: an undeclared
  exception terminates the iOS process. Example: `SaveActivityUseCase`. Enforced: reviewer only.
  Severity: blocking.
- **C5** Android: work in `onReceive`, `onStartCommand` or another component callback stays inside
  its time limit (a receiver 10 s, `startForeground` within 5 s of `startForegroundService`);
  anything longer moves to a coroutine or worker. Why: the system kills or ANRs the app. Example:
  `TrackingService.onStartCommand` calls `startForeground` first. Enforced: reviewer only.
  Severity: blocking.

## Exceptions

- **E1** Catch the narrowest type that the code can handle; a broad `Exception` only at a boundary
  that maps every failure (repository, ViewModel, `SafeApiCall`), never `Throwable`. Why: a broad
  catch hides bugs and can swallow `Error`s. Example: `SafeApiCall.kt`, `RouteViewModel`'s
  `catch (e: CancellationException) { throw e } catch (_: Exception)`. Enforced: detekt
  `TooGenericExceptionCaught` and `TooGenericExceptionThrown` (on by default, `@Suppress` needs
  human approval). Severity: blocking.
- **E2** Never swallow an exception: handle it, rethrow it, or turn it into state or an event; the
  rules are `tm-pr-review` item 13 and `tm-kmp-shared` ("Cancellation"). Why: a swallowed failure
  is invisible to the user and to the next developer. Example: `TrackingViewModel` Finish
  (`keepForRetry` plus `ShowError`). Enforced: detekt `SwallowedException` (on by default; an
  exception named `_` is not checked), SwiftLint `optional_try`. Severity: blocking.
- **E3** An error the user can act on reaches the UI state through the existing error model
  (`RouteError` to `RouteUiError`, `tm-kmp-shared` "Existing error model"), not a log line. Why: a
  logged error leaves the screen as if it worked. Example: `TrackingViewModel` (`ShowError`).
  Enforced: reviewer only. Severity: blocking.
- **E4** The failure of a background job (a coroutine, a `Task`, a service) is observable as state
  or an event, not lost. Why: a failed save or sync the user never hears about is data loss.
  Example: `ObserveActivitiesUseCase` emits `Failed`. Enforced: reviewer only. Severity: blocking.

## Dispatchers and threads

- **D1** No hard-coded `Dispatchers.*` in a class, not as a default argument either: inject a
  `CoroutineDispatcher` (or a scope); only a DI module and the application root name `Dispatchers`.
  Why: a test cannot replace it. Example: the DI module `CommonTrackingModule` names
  `Dispatchers.Default` (scope). Enforced: detekt `InjectDispatcher` (type resolution: plain
  detekt never fires, see deviations). Severity: blocking.
- **D2** `Main` for UI state only, `IO` for blocking IO, `Default` for CPU work. Why: a wrong pool
  starves the UI or the IO threads. Example: `ActivityHistoryRepositoryImpl` (IO). Enforced:
  reviewer only. Severity: blocking when it puts blocking work on `Main` (C1), else important.
- **D3** The `withContext` switch lives once, in the layer that does the blocking work (the
  repository or data source), never in a ViewModel or use case. Why: the caller then needs no
  knowledge of what blocks. Example: `ActivityHistoryRepositoryImpl`, `UserProfileRepositoryImpl`.
  Enforced: reviewer only. Severity: important.
- **D4** No `Dispatchers.Unconfined` and no `GlobalScope` in production code. Why: no lifecycle,
  no cancellation, untestable ordering. Example: none in production code. Enforced: detekt
  `ForbiddenImport` (`GlobalScope` import only); `Unconfined` reviewer only. Severity: blocking.
- **D5** Tests inject a test dispatcher (`tm-testing`, `tm-android` "Tests"). Why: real
  dispatchers make tests slow and flaky. Example: `tm-testing`. Enforced: reviewer only.
  Severity: important.
- **D6** iOS: UI-facing types are `@MainActor`; no blocking work in `body` or on the main actor.
  Why: the same as C1. Example: `HistoryViewModel` (`@MainActor`). Enforced: reviewer only.
  Severity: blocking when it blocks the main actor, else important.

## Process death and lifecycle

- **R1** Android: UI state that must survive is in `SavedStateHandle` or `rememberSaveable`, data
  that must survive is persisted, and a ViewModel is never the only holder of something the user
  would lose. Why: the system kills a backgrounded process at any time. Example: no example yet
  (no `SavedStateHandle` or `rememberSaveable` in the code). Enforced: reviewer only. Severity:
  important (blocking when the loss is data the user entered or recorded).
- **R2** Android: a foreground service restores or restarts the in-progress session after process
  death, or the app tells the user it is gone. Why: `START_STICKY` restarts the service with no
  state. Example: no example yet; `TrackingSessionManager` keeps the session only in memory and
  `TrackingService` restarts empty (see deviations). Enforced: reviewer only. Severity: important.
- **R3** Android: collect flows in composition with `collectAsStateWithLifecycle()`. Why: a plain
  `collectAsState` collects while the app is in the background. Example: the four screens' Root
  composables. Enforced: reviewer only (no lint check for it in the repo today). Severity:
  important.
- **R4** Android: no `Context`, `View` or `Activity` held in a ViewModel or a singleton; an
  `Application` context is the only one a long-lived object may hold. Why: it leaks the screen.
  Example: the four ViewModels hold none. Enforced: Android lint `StaticFieldLeak` (on by
  default, static fields only); reviewer only for the rest. Severity: blocking.
- **R5** iOS: a scene-phase change or app termination while tracking persists or restores the
  in-progress session; no work assumes the app stays in the foreground. Why: iOS suspends and
  terminates apps without a callback you can rely on. Example: no example yet (no `scenePhase` use;
  background location is enabled by `IosLocationRepositoryImpl.setBackgroundUpdatesEnabled`).
  Enforced: reviewer only. Severity: important (blocking when the loss is a recorded session).
- **R6** iOS: cancel or release observers, timers and location updates when the owner goes away.
  Why: they keep firing into a dead screen. Example: `TrackingViewModel.deinit` cancels its tasks.
  Enforced: reviewer only. Severity: blocking (it is M1).

## Memory and leaks

- **M1** Whatever is registered is unregistered by the owner that registered it: listeners,
  callbacks, `BroadcastReceiver`s, sensor and location updates, observers, timers,
  `DisposableEffect`/`onDispose`, `deinit`. Why: a registration holds its owner alive. Example:
  `AndroidLocationRepositoryImpl.observeLocationUpdates` (`awaitClose { removeLocationUpdates }`),
  `TrackingLiveActivityController` (observer added in `init`, removed in `deinit`). Enforced:
  reviewer only on Android (no lint check for listener registration); SwiftLint
  `notification_center_detachment` (on), `discarded_notification_center_observer` (off).
  Severity: blocking.
- **M2** No `Context`, `Activity`, `View` or composable lambda held by a ViewModel, singleton,
  companion object or long-lived coroutine. Why: it outlives the screen it belongs to. Example:
  `AndroidTrackingServiceLauncher` holds a `Context` injected by Koin (application context only).
  Enforced: Android lint `StaticFieldLeak` (static fields only); reviewer only for the rest.
  Severity: blocking.
- **M3** A coroutine runs in a scope that ends with its owner (`viewModelScope`, a scope the DI
  container or the service closes), never `GlobalScope`. Why: otherwise it runs after the owner is
  gone. Example: `TrackingService` cancels `serviceScope` in `onDestroy`. Enforced: detekt
  `ForbiddenImport` for `GlobalScope`; the rest reviewer only. Severity: blocking.
- **M4** Flows are collected in the owner's lifecycle (R3 on Android, a `.task` modifier or a stored
  `Task` cancelled in `deinit` on iOS, `tm-ios` "SKIE interop"). Why: a collector outlives its
  screen. Example: `HistoryView` (`.task { await viewModel.observe() }`). Enforced: reviewer only.
  Severity: important.
- **M5** A bitmap, snapshot or large buffer is released or downsampled before it is held or saved.
  Why: bitmaps are the usual out-of-memory crash. Example: `saveSnapshotToFile` scales to 600 px
  wide (it does not recycle the original). Enforced: reviewer only (Android lint `Recycle` covers
  streams and cursors, not bitmaps). Severity: important.
- **M6** Swift: a closure stored by an object that outlives the caller captures `self` weakly
  (`[weak self]`); delegates are `weak`; a `Timer` or `NotificationCenter` observer is invalidated or
  removed; no strong cycle between a view model and its closures or publishers. Why: a cycle never
  deinits. Example: `TrackingViewModel` (`[weak self]` in both observation tasks and the stop
  closure). Enforced: SwiftLint `weak_delegate` and `unowned_variable_capture` are off; the rest
  reviewer only. Severity: blocking for a stored closure with a strong `self`, else important.
- **M7** Caches are bounded (a maximum size or count, as `maxPendingEvents` is in the iOS view
  models). Why: an unbounded cache is a slow leak. Example: `TrackingViewModel.maxPendingEvents`.
  Enforced: reviewer only. Severity: important.
- **M8** Android: a debug build runs a leak check: LeakCanary or the `StrictMode` VM policy
  (`detectLeakedClosableObjects`, `detectActivityLeaks`). Why: leaks are found by running, not
  reading. Example: no example yet (neither exists: see deviations). Enforced: reviewer only.
  Severity: important.

## Performance and efficiency

- **P1** Compose: a stable `key` in every lazy list (`LazyColumn`, `LazyVerticalGrid`). Why: without
  it items lose state and recompose on reorder. Example: `HistoryScreen` (`key = { it.id }`).
  Enforced: reviewer only. Severity: important.
- **P2** Compose: no heavy work or allocation in composition; `remember` or `derivedStateOf` for a
  derived value; read state as late as possible; no new lambda or object per item where it breaks
  skipping. Why: composition runs on every state change. Example: `RoutePolyline`
  (`remember(points) { ... }`). Enforced: reviewer only. Severity: important.
- **P3** SwiftUI: a cheap `body`, observation as narrow as the state, no heavy work in `body`. Why:
  `body` runs on every published change. Example: no example yet. Enforced: reviewer only.
  Severity: important (blocking when it blocks the main actor: D6).
- **P4** A per-location-update or per-tick path allocates little and is conflated or sampled before
  it reaches the UI (map polylines especially). Why: it runs for as long as the session. Example:
  no example yet (see deviations). Enforced: reviewer only. Severity: important.
- **P5** Room: queries run off the main thread, a filtered or sorted column has an index, no query
  per item (N+1), no loading a whole table for one row. Why: query cost grows with the table.
  Example: `ActivityDao.getById` (primary key); the sorted `startedAtEpochMillis` has no index (see
  deviations). Enforced: reviewer only; a new index is a schema change (`tm-kmp-shared`).
  Severity: important.
- **P6** Battery: the location priority and interval are the lowest that meet the feature, and
  updates stop when no screen or session needs them. Why: location is the largest battery cost.
  Example: `TrackingSessionManager.pause` cancels the observation. Enforced: reviewer only.
  Severity: important.
- **P7** Images and snapshots are downsampled and released (see M5). Why: memory and storage grow
  with pixels. Example: `saveSnapshotToFile`. Enforced: reviewer only. Severity: important.

## Mechanical rules

Rules that a tool can check go to the tool, not to more prose here. The measured hits of the
tools that are not enabled today are in the PR that wrote this skill and in the board record
`enable-robustness-lint-rules`; do not add a prose rule for something a tool rule would check.

## Known deviations in the current code

Don't copy these as a pattern for new code. Each names its board record.
- No `StrictMode` policy and no LeakCanary anywhere in the app (M8; `strictmode-leak-detection-debug`).
- `TrackingService` creates `CoroutineScope(SupervisorJob() + Dispatchers.Default)` itself;
  `TrackingViewModel`, `UserProfileRepositoryImpl` and `ActivityHistoryRepositoryImpl` name
  `Dispatchers.IO` as a default argument (D1; `inject-dispatchers-from-di`).
- The map snapshot is scaled, PNG-encoded and written on the main thread: Android `saveSnapshotToFile`
  in the `map.snapshot { }` callback, iOS `saveMapSnapshot` in `TrackingMapView` (C1, D6;
  `snapshot-save-off-main-thread`).
- The in-progress tracking session lives only in `TrackingSessionManager`'s in-memory
  `MutableStateFlow`: after Android process death `TrackingService` (`START_STICKY`) restarts with
  `Idle` state and no location collection, and after iOS termination the session is gone (R2, R5;
  `tracking-session-lost-on-process-death`).
- The route draft (start point, waypoints, generated route) lives only in `RouteViewModel` and its
  Swift twin (R1; `route-draft-lost-on-process-death`).
- Every location update copies the whole path (`path + coordinates` in `UpdateTrackingStateUseCase`)
  and the polyline is rebuilt from it; no conflation or distance filter on either platform (P4,
  P6; `tracking-location-update-path-cost`).
- `tbl_activities` has no index on the sorted `startedAtEpochMillis` and the history list reads
  whole rows including both coordinate lists (P5; `history-query-index-and-columns`).
- detekt `InjectDispatcher`, `UnsafeCast`, `SleepInsteadOfDelay` and `RedundantSuspendModifier` are
  on by default but need type resolution; the gate runs plain `detekt` (`enable-robustness-lint-rules`).
