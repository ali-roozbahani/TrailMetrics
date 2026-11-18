# Memory and leaks (M1, M2, M3, M5, M6, M7, M8, M9)

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the section "Memory and leaks". The rules are unchanged; they are still cited as `tm-robustness`, rules M1, M2, M3, M5, M6, M7, M8 and M9.

## Memory and leaks

- **M1** Whatever is registered is unregistered by the owner that registered it: listeners,
  callbacks, `BroadcastReceiver`s, sensor and location updates, observers, timers,
  `DisposableEffect`/`onDispose`, `deinit` (on iOS: cancel or release them when the owner goes
  away). Why: a registration holds its owner alive and keeps firing into a dead screen. Example:
  `TrackingViewModel.deinit` cancels its tasks,
  `AndroidLocationRepositoryImpl.observeLocationUpdates` (`awaitClose { removeLocationUpdates }`),
  `TrackingLiveActivityController` (observer added in `init`, removed in `deinit`). Enforced:
  reviewer only on Android (no lint check for listener registration); SwiftLint
  `notification_center_detachment` (on), `discarded_notification_center_observer` (off).
  Severity: blocking.
- **M2** Android: no `Context`, `Activity`, `View` or composable lambda held by a ViewModel,
  singleton, companion object or long-lived coroutine; an `Application` context is the only one a
  long-lived object may hold. Why: it outlives the screen it belongs to and leaks it. Example: the
  four ViewModels hold none; `AndroidTrackingServiceLauncher` holds a `Context` injected by Koin
  (application context only).
  Enforced: Android lint `StaticFieldLeak` (static fields only); reviewer only for the rest.
  Severity: blocking.
- **M3** A coroutine runs in a scope that ends with its owner (`viewModelScope`, a scope the DI
  container or the service closes), never `GlobalScope`. Why: otherwise it runs after the owner is
  gone. Example: `TrackingService` cancels `serviceScope` in `onDestroy`. Enforced: detekt
  `ForbiddenImport` for `GlobalScope`; the rest reviewer only. Severity: blocking.
- **M5** An image, bitmap, snapshot or large buffer is released or downsampled before it is held or
  saved. Why: bitmaps are the usual out-of-memory crash, and memory and storage grow with pixels.
  Example: `saveSnapshotToFile` scales to 600 px
  wide and recycles the scaled copy. Enforced: reviewer only (Android lint `Recycle` covers
  streams and cursors, not bitmaps). Severity: important.
- **M6** Swift: a closure stored by an object that outlives the caller captures `self` weakly
  (`[weak self]`); delegates are `weak`; a `Timer` or `NotificationCenter` observer is invalidated or
  removed; no strong cycle between a view model and its closures or publishers. Why: a cycle never
  deinits. Example: `TrackingViewModel` (`[weak self]` in both observation tasks and the stop
  closure). Enforced: SwiftLint `weak_delegate` and `unowned_variable_capture` are off; the rest
  reviewer only. Severity: blocking for a stored closure with a strong `self`, else important.
  A leak test (the iOS side of M8): make the object in a scope, keep a `weak var` to it, drop the strong
  reference, run the pending work (`await` the tasks it started), then `XCTAssertNil` the weak
  reference; do it for each type that stores a closure or a `Task` over `self`.
- **M7** Caches are bounded (a maximum size or count, as `maxPendingEvents` is in the iOS view
  models). Why: an unbounded cache is a slow leak. Example: `TrackingViewModel.maxPendingEvents`.
  Enforced: reviewer only. Severity: important.
- **M8** Android: a debug build runs a leak check: LeakCanary or the `StrictMode` VM policy
  (`detectLeakedClosableObjects`, `detectActivityLeaks`). Why: leaks are found by running, not
  reading. Example: `TrailMetricsApplication` installs `installDebugStrictMode` (`DebugStrictMode.kt`) in
  debug builds (a release build has no policy): a thread policy (`detectAll`) and a VM policy (leaked
  closables, activities and SQLite objects), penalty log, not death (a crash would make the instrumented
  tests flaky on CI emulators). It reports what the framework instruments: a disk or network call on the
  main thread, a closable, `Activity` or SQLite object that is garbage collected unclosed. It does not catch
  a leaked `View`, `Fragment` or `ViewModel`, a leak through the app's own scope or listener, or a long
  computation on the main thread. Enforced: reviewer only. Severity: important.
- **M9** A new non-UI class (a use case, repository, manager or saver) does not create or keep a
  `CoroutineScope` and does not launch from `init`: it exposes `suspend` functions or a `Flow`, or its
  owner starts it with one named `start(scope)` call. Why: a launch from `init` runs before the object
  is fully built and a test cannot step it, and a kept scope needs someone to cancel it. Example: no
  example yet. Enforced: reviewer only. Severity: important. Not a finding: a ViewModel's
  `viewModelScope`, a service scope that `onDestroy` cancels (M3), a scope a DI module creates and hands in,
  or a class that exists today (see "Known deviations in the current code", `SKILL.md`).
