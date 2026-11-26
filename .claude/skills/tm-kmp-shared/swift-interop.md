# SKIE and Swift-facing API design, the `@Throws` policy, iOS location (L1)

Moved from `SKILL.md`, word for word except the references that now name this skill's files: the sections "SKIE and Swift-facing API design" (with "`@Throws` policy (Kotlin called from Swift)") and "iOS location (L1)". The rules are unchanged; they are still cited as `tm-kmp-shared`, "SKIE and Swift-facing API design", "`@Throws` policy" and "iOS location (L1)".

## SKIE and Swift-facing API design

- Kotlin sealed interfaces become Swift enums via `onEnum(of:)` (see `TrackingState` used
  as `switch onEnum(of: trackingState) { case .tracking(let data): ... }`). Keep sealed
  hierarchies flat and exhaustive-friendly.
- `Flow`/`SharedFlow` becomes `AsyncSequence`, consumed with `for await`. An
  `AsyncStream` has ONE consumer for its lifetime — never store a `Flow` as a `let`
  and hand out multiple `for await` loops on it. Use a fresh `makeStream()` +
  continuation per consumer, matching `TrackingViewModel.makeEventsStream()`.
- Kotlin coroutine scopes may run on `Dispatchers.Default`; resumption in Swift after
  `for await` is NOT guaranteed to land on the MainActor even inside an `@MainActor`
  class. Hop explicitly with `await MainActor.run { ... }` around any state mutation,
  as both `observeTrackingState()` and `observeLocationIssues()` do.
- Prefer domain types that cross cleanly (Long, Double, sealed types). Verify the
  inferred Swift type for anything generic before relying on it.

### `@Throws` policy (Kotlin called from Swift)

Kotlin/Native delivers to Swift only the exceptions a function lists in `@Throws` (plus
`CancellationException` for suspend functions); any other exception reaching the boundary
terminates the process. SKIE makes every `suspend fun` `async throws` in Swift, so `try await`
looks safe even when the Kotlin side declares nothing.
1. Every Kotlin function Swift calls (or a Swift fake implements) that can throw declares
   `@Throws`; suspend functions list `CancellationException` explicitly.
2. Failures the UI shows specifically are `RouteError`. A function declaring
   `@Throws(RouteError::class, ...)` maps every failure to a `RouteError`.
3. Persistence-backed functions declare `@Throws(Exception::class, CancellationException::class)`,
   never `Throwable` (an `Error` such as OutOfMemoryError should crash). No new `RouteError` cases
   for them; Swift shows `RouteUiErrorGeneral`.
4. Swift never drops an error: no `try?` hiding a failure, no `Task { try ... }` without `do/catch`.
5. After a failure, state stays consistent (nothing half-updated, no navigation).
6. New Swift-visible API that needs no policy change: a data class, an enum case or a read-only
   `StateFlow`/`val` property on a domain type Swift already uses, a new function that cannot throw (not
   `suspend`, no `@Throws`, and nothing in it can throw: it only reads or sets state, as
   `UnsavedSessionWarning.markShown()` does), a new class whose Swift-visible members are only read-only
   `StateFlow` properties and such functions (`UnsavedSessionWarning`, with `isRaised`; owner decision of
   2026-11-25), and a parameter or return type
   added to (or swapped on) a function that already declares its `@Throws` or cannot throw. Allowed
   when (a) no existing `@Throws` is removed or changed, (b) a new function that can throw follows
   rules 1 to 3, (c) a new `Flow` that Swift iterates and that can fail gets the
   `ObserveActivitiesUseCase` treatment below (a `StateFlow` that never fails needs none), (d) the
   Swift fakes and callers are updated in the same PR, and (e) the PR description lists each new
   Swift-visible name under the heading `Swift-visible API`. Removing or changing a `@Throws` and a
   new failing Flow Swift iterates stay an escalation. A new getter on `KoinHelper` (step 2 of
   "Adding a dependency iOS needs") does not escalate when all of these hold: (a) it is concrete
   and non-generic, and its body only resolves the binding the way the neighbouring getters do
   (`get()` or their `by inject()` property), no other logic; (b) the binding it returns is added
   in the same PR in a `shared`/`data` Koin module (step 1); (c) `KoinGraphCheck` and the Swift
   fakes and callers are updated in the same PR; (d) the PR description lists the getter under
   `Swift-visible API`. Still an escalation: removing, renaming or changing an existing getter, a
   getter with logic, and any other change to `KoinHelper`, to `KoinInit`'s module list beyond
   adding the binding of (b), or to how Koin starts.

Today: `GenerateClosedRouteUseCase`, `GetCurrentLocationUseCase` follow rule 2 (their
repositories return `RouteError` failures). `SaveActivityUseCase`, `UserProfileRepository` and
`ActivityHistoryRepository`'s suspend members follow rule 3. `UserProfileRepository.getUserProfile`
returns `null` for "nothing saved" and throws `StoredUserProfileUnreadableException` (an `Exception`,
so rule 3 covers it) for a stored value that cannot be decoded; the value stays in storage until a
new profile overwrites it. `observeActivities()` is a `Flow`,
which `@Throws` doesn't cover: a failing Flow terminates the iOS app (SKIE collects it in a
coroutine scope with no handler, and its Swift iterator `fatalError`s on the error). Swift
therefore doesn't iterate it directly: `ObserveActivitiesUseCase` (domain) maps each emission to
`ActivitiesUpdate.Loaded` and turns an `Exception` (never an `Error` or cancellation), thrown
when `observeActivities()` is called or while collecting, into one `ActivitiesUpdate.Failed`,
then completes; `invoke()` itself never throws. The iOS and Android `HistoryViewModel`s both
consume that. A new Flow that Swift iterates and that can fail needs the same treatment.

## iOS location (L1)

Decided by the owner and in the code since `ios-always-location-removal`: `IosLocationRepositoryImpl` requests
when-in-use authorization only, and `Info.plist` has no Always usage string.

- The app asks for when-in-use authorization only, and tracks in the background through the `location`
  background mode (`UIBackgroundModes` in `Info.plist`) with `allowsBackgroundLocationUpdates = true`
  while a session runs. A session starts while the app is in the foreground.
- No `requestAlwaysAuthorization()` and no `NSLocationAlwaysAndWhenInUseUsageDescription` unless a
  feature that needs the app relaunched after termination is built; that is an owner decision with its
  own App Review note.
- While a session runs: `allowsBackgroundLocationUpdates` true, `pausesLocationUpdatesAutomatically`
  false, `activityType` fitness; all three are put back when it ends (`applyBackgroundTracking`,
  proved by `BackgroundTrackingSettingsTest`).
- The authorization status is read at the use site (`ensureLocationPermission`) and never cached; a
  refusal is `RouteError.MissingLocationPermission`, as on Android.
- A simulator cannot show the behavior with the screen off, so no test proves it: a change here
  ends with a short device check by the owner.
- Enforced: reviewer only. Violation: `important`.
