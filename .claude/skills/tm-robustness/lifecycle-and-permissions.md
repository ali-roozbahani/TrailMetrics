# Intents and permissions, process death and lifecycle (S1, S2, R1, R2, R3, R5, R7)

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the sections "Intents and permissions" and "Process death and lifecycle". The rules are unchanged; they are still cited as `tm-robustness`, rules S1, S2, R1, R2, R3, R5 and R7.

## Intents and permissions

- **S1** Android: an exported component (the launcher `Activity`, any exported service, receiver or
  provider) never acts on a destructive or privileged action carried by its `Intent` unless only we can
  have sent it: a non-exported target, or a secret that only our own `PendingIntent` holds. An action
  string or an extra's name is public, so it proves nothing. A `PendingIntent` is `FLAG_IMMUTABLE` with
  an explicit target. Why: any app can send an intent to an exported component, and the action here
  can discard the user's recording. Example: `MainActivity.handleStopTrackingIntent` acts on the Stop
  action only with the secret of `StopTrackingAuthorization`, which `TrackingService`'s Stop
  `PendingIntent` (explicit, immutable) carries. Enforced: reviewer only. Severity: blocking.
- **S2** Android: a runtime permission is handled in all three outcomes: granted; the system asks for
  an explanation (a rationale before the next request); refused for good (a way to the app's settings).
  A refusal is never a silent no-op, and the result is never cached: the use site asks the system, and
  a `SecurityException` becomes the typed error (E3). Why: a user who refused twice has no other way
  back, and a cached grant outlives the user's change in settings. Example:
  `AndroidLocationRepositoryImpl` maps `SecurityException` to `MissingLocationPermission` and holds no
  permission state; the launchers do not meet the rest (see "Known deviations in the current code", `SKILL.md`). Enforced: reviewer only.
  Severity: important.

## Process death and lifecycle

- **R1** Android: UI state that must survive is in `SavedStateHandle` or `rememberSaveable`, data
  that must survive is persisted, and a ViewModel is never the only holder of something the user
  would lose. Why: the system kills a backgrounded process at any time. Example: `RouteViewModel`
  persists the plan through `RouteDraftKeeper` (Room) and restores it at creation (no `SavedStateHandle`
  or `rememberSaveable` in the code). Enforced: reviewer only. Severity:
  blocking when the reviewer verifies in the files the loss of data the user recorded or entered
  (the session, the route draft, a saved activity), important for a likely gap the files cannot
  prove.
- **R2** Android: a foreground service restores or restarts the in-progress session after process
  death, or the app tells the user it is gone. Why: `START_STICKY` restarts the service with no
  state. Example: `TrackingService` restores the stored session on a restart with no intent and leaves
  a notice for a paused or finished one (`handleRestart`); `SavedSessionOfferViewModel` offers it at
  the app start. Enforced: reviewer only. Severity: blocking
  when the reviewer verifies in the files the loss of data the user recorded or entered (the
  session, the route draft, a saved activity), important for a likely gap the files cannot prove.
- **R3** Collect flows in the owner's lifecycle: on Android in composition with
  `collectAsStateWithLifecycle()`, on iOS in a `.task` modifier or a stored `Task` cancelled in
  `deinit` (`tm-ios` "SKIE interop"). Why: a plain `collectAsState` collects while the app is in the
  background, and any collector outlives its screen. Example: the four screens' Root composables,
  `HistoryView` (`.task { await viewModel.observe() }`). Enforced: reviewer only. No lint check for
  it exists in the repo today. Severity: important.
- **R5** iOS: a scene-phase change or app termination while tracking persists or restores the
  in-progress session; no work assumes the app stays in the foreground. Why: iOS suspends and
  terminates apps without a callback you can rely on. Example: `SavedSessionOfferModel` restores the
  stored session once per launch and offers it (no `scenePhase` use; background location is enabled by
  `IosLocationRepositoryImpl.setEnabled`, the `BackgroundLocationUpdates` of `domain`).
  Enforced: reviewer only. Severity: blocking when the reviewer verifies in the files the loss of
  data the user recorded or entered (the session, the route draft, a saved activity), important
  for a likely gap the files cannot prove.
- **R7** iOS: a Live Activity is given a `staleDate` and the widget draws the stale case
  (`context.isStale`), and a value that moves on its own (elapsed time) is drawn by the system from a
  start date, not pushed as a number. Why: the app can be suspended or killed while tracking, and a
  frozen number on the lock screen reads as live. Example: `TrackingLiveActivityController` (stale date,
  timer anchored to `timerStart`) and the widget's `ElapsedTimerText`. Enforced: reviewer only. Severity:
  important.
