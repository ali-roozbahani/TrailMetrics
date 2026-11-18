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
of detekt 1.23.8; "plain" detekt is the gate's `detekt` task, which has no type resolution, and "typed"
is `detektTyped`, which the gate and CI also run (see "Mechanical rules").

## Topic files

Rule ids are unchanged: a finding cites the id, and the id is in this file or in the file named here. Read a topic
file when the task or the diff reaches its topic, not before; a reviewer reads it for a diff that touches the topic.

| File | Rules | Read it when |
|---|---|---|
| `SKILL.md` (this file) | C1 to C6, E1 to E4, D1 to D7 | every Kotlin or Swift change |
| `lifecycle-and-permissions.md` | S1, S2, R1, R2, R3, R5, R7 | a change touches an exported component or an `Intent`, a runtime permission, saved or restored state, a service or a Live Activity, a scene phase, or how a flow is collected |
| `memory-and-leaks.md` | M1, M2, M3, M5, M6, M7, M8, M9 | a change adds a non-UI class that creates or keeps a `CoroutineScope` or launches from `init`, or registers a listener, observer, receiver, timer or callback, keeps a `Context`, a closure or a coroutine in a long-lived object, holds an image or a cache, or adds a leak check |
| `performance.md` | P1 to P6, P8, P9 | a change touches a lazy list, composition or `body` work, a per-update or per-tick path, a Room query, location priority or interval, or `@Stable`/`@Immutable` |


## Crashes and ANR

- **C1** No blocking call (file, database, network, `runBlocking`, `Thread.sleep`, heavy
  computation) on the main thread or in a lifecycle callback (`onCreate`, `onReceive`,
  `onStartCommand`, `body`, `init`). Why: the main thread drives input and drawing; 5 s blocked is
  an ANR. Example: `ActivityHistoryRepositoryImpl` (`withContext(ioDispatcher)`). Enforced:
  reviewer only (`runBlocking` has no rule; detekt `SleepInsteadOfDelay`, typed, reports
  `Thread.sleep` inside a suspend function). Severity: blocking.
- **C2** Never `!!`, read a `lateinit` before it is set, or use an unchecked cast or an index on
  external data (network, disk, intent extras, nav arguments); use `checkNotNull(x) { "why" }`,
  `as?`, `getOrNull`. Why: each throws on input you do not control. Example: no `!!` and no
  `lateinit` in production Kotlin. Enforced: detekt `UnsafeCallOnNullableType` (on by default),
  `CastToNullableType` and `LateinitUsage` (production code; test source sets are excluded); the
  compiler rejects a cast that can never succeed (`allWarningsAsErrors`), so detekt `UnsafeCast` adds
  nothing; index access reviewer only. Severity: blocking.
- **C3** Swift: never a force unwrap `!`, `try!` or `as!` on external data. Why: each traps and
  kills the process. Example: none in production Swift. Enforced: SwiftLint `force_unwrapping`,
  `force_try`, `force_cast` (all errors). Severity: blocking.
- **C4** An exception thrown by Kotlin that Swift calls follows the `@Throws` policy in
  `tm-kmp-shared` ("`@Throws` policy", `swift-interop.md`); do not restate it there or here. Why: an undeclared
  exception terminates the iOS process. Example: `SaveActivityUseCase`. Enforced: reviewer only.
  Severity: blocking.
- **C5** Android: work in `onReceive`, `onStartCommand` or another component callback stays inside
  its time limit (a receiver 10 s, `startForeground` within 5 s of `startForegroundService`);
  anything longer moves to a coroutine or worker. Why: the system kills or ANRs the app. Example:
  `TrackingService.onStartCommand` calls `startForeground` first. Enforced: reviewer only.
  Severity: blocking.
- **C6** Android: an attached `View` (a `MapView` and the callbacks of the Maps SDK included) is read
  or changed only on the main thread. Why: a change from another thread can leave a sync barrier in
  the main thread's message queue, which then stops handling messages with no crash and no log (an
  ANR; fixed only from Android 17). Example: no example yet. Enforced: reviewer only. Severity:
  blocking.

**Judging C1.** A finding of C1 proves two things in its text: the thread, as the chain of callers from
the entry point (a lifecycle callback, a composable body, a `viewModelScope` or `lifecycleScope`
launch, which run on `Main`) down to the call, quoted caller by caller; and that the call blocks.
These are not findings: reading `StateFlow.value` or a flow seeded with its value; a suspending call
(it suspends, it does not block the thread); `runBlocking` on a worker thread, which blocks that
worker only; a wait of a frame or two. Leave out what the chain does not prove.

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
  Accepted exception (owner, PR #250): the route draft. `RouteDraftSaver` logs a failed save or read,
  planning goes on, no notice; the plan is cheap to make again, not data the user recorded.

## Dispatchers and threads

- **D1** No hard-coded `Dispatchers.*` in a class, not as a default argument either: inject a
  `CoroutineDispatcher` (or a scope); only a DI module and the application root name `Dispatchers`.
  Why: a test cannot replace it. Example: the DI module `CommonTrackingModule` names
  `Dispatchers.Default` (scope). Enforced: detekt `InjectDispatcher` (typed run; it
  skips `di/*Module.kt` and the test source sets). Severity: blocking.
- **D2** `Main` for UI state only, `IO` for blocking IO, `Default` for CPU work. Why: a wrong pool
  starves the UI or the IO threads. Example: `ActivityHistoryRepositoryImpl` (IO). Enforced:
  reviewer only. Severity: blocking when it puts blocking work on `Main` (C1), else important.
- **D3** The `withContext` switch lives once, in the layer that does the blocking work (the
  repository or data source), never in a ViewModel or use case. Why: the caller then needs no
  knowledge of what blocks. Example: `ActivityHistoryRepositoryImpl`, `UserProfileRepositoryImpl`.
  Enforced: reviewer only. Severity: important.
- **D4** No `Dispatchers.Unconfined` and no `GlobalScope` in production code. Why: no lifecycle,
  no cancellation, untestable ordering. Example: none in production code. Enforced: detekt
  `ForbiddenImport` (`GlobalScope` import) and `GlobalCoroutineUsage` (typed run); `Unconfined`
  reviewer only. Severity: blocking.
- **D5** Tests inject a test dispatcher (`tm-testing`, `tm-android` "Tests"). Why: real
  dispatchers make tests slow and flaky. Example: `tm-testing`. Enforced: reviewer only.
  Severity: important.
- **D6** iOS: UI-facing types are `@MainActor`; no blocking work in `body` or on the main actor.
  Why: the same as C1. Example: `HistoryViewModel` (`@MainActor`). Enforced: reviewer only.
  Severity: blocking when it blocks the main actor, else important.
- **D7** iOS: a `Task { }` made in a `@MainActor` context inherits the main actor, so blocking work in
  any statement of its body (early-return, cancellation and cleanup branches included) goes to
  `Task.detached` or an explicit non-main executor. Why: the same as C1 and D6. Whether a
  `nonisolated async` function hops off its caller depends on the module that defines it (the app
  target has `SWIFT_APPROACHABLE_CONCURRENCY`, the six `Package.swift` files do not): do not reason
  from a doc comment. To run blocking work off the main actor without `Task.detached`, mark the
  function `@concurrent` (it always runs on the global executor): one compile check in a package
  with the shape of ours (tools-version 5.9, language mode 5, `.iOS("26.5")`) accepted it. Example: #219 called `discardSnapshotFile` (`FileManager.removeItem`) in the
  cancel branch of `TrackingMapView`'s snapshot `Task`, on the main actor, until `Task.detached`.
  Enforced: reviewer only. Severity: blocking when it blocks the main actor, else important.


R4, R6, M4, P7 are merged into M2, M1, R3, M5.

## Mechanical rules

Rules that a tool can check go to the tool, not to more prose here. Do not add a prose rule for
something a tool rule would check. The gate and CI run `./gradlew detekt detektTyped`: the plain task
reads every source set, the typed one resolves types in the Android and common source sets of every
module (`iosMain` and `iosTest` get the plain task only: detekt 1.23.8 has no type resolution for
them). These robustness rules fire (each shown on a planted case): `InjectDispatcher`,
`SleepInsteadOfDelay`, `GlobalCoroutineUsage`, `CastToNullableType`, `LateinitUsage`,
`ElseCaseInsteadOfExhaustiveWhen`, `ThrowingExceptionInMain` and `NotImplementedDeclaration`.
detekt 1.23.8 embeds Kotlin 2.0.21 and cannot read the metadata of Kotlin 2.4 libraries, so a call of a
Kotlin-declared library function stays unresolved. Off for that reason, with the reason in
`config/detekt/detekt.yml`: `RedundantSuspendModifier` (false hits on `delay` and `collect`) and
`SuspendFunSwallowedCancellation`; `ForbiddenMethodCall` does not fire for `println` and `print` (`scripts/check-no-println.sh` does).

## Known deviations in the current code

Don't copy these as a pattern for new code. Each names its board record.
- The location launchers in `RouteScreen` and `TrackingScreen` do nothing on a refusal, there is no
  rationale and no way to the app's settings, and the notification permission is asked on every entry
  with an empty result (S2; `android-location-permission-denial-and-disclosure`).
- `TrackingSessionManager` keeps a scope (`scope`) and launches `_state.collect { persist(it) }` from
  `init`; `RouteDraftSaver` has the same shape. Both are documented in the code and stay as they are
  (M9).
- `IosTrackingServiceLauncher` takes the concrete
  `IosLocationRepositoryImpl` (`ios-launcher-depends-on-concrete-location-repository`); the iOS
  `TrackingViewModel` recomputes metrics and calories that belong in `domain`
  (`tracking-metrics-calories-to-domain`).
- Every location update copies the whole path (`path + coordinates` in `UpdateTrackingStateUseCase`)
  and the polyline is rebuilt from it; no conflation or distance filter on either platform (P4,
  P6; `tracking-location-update-path-cost`).
- `tbl_activities` has no index on the sorted `startedAtEpochMillis` and the history list reads
  whole rows including both coordinate lists (P5; `history-query-index-and-columns`).
- detekt does not check `runCatching`
  around a suspend call, or a redundant `suspend`; see "Mechanical rules".
