# data

KMP module implementing the repository interfaces declared in `domain`.
Targets: `android`, `iosArm64`, `iosSimulatorArm64` (no `iosX64` — Room 3.0.2
does not publish that target yet).

## What lives here

- **Repository implementations** (`local/repository/`, `directions/`,
  `user/`): `ActivityHistoryRepositoryImpl` (Room), `DirectionsRepositoryImpl`
  (Ktor), `UserProfileRepositoryImpl` (built on the `KeyValueStorage`
  expect/actual).
- **Room persistence** (`local/`): `TrailMetricsDatabase`, DAOs, entities,
  converters. Fully shared in `commonMain` — Room 3.x provides a
  context-free, Kotlin/Native-compatible builder.
- **Networking** (`directions/`, `common/PlatformHttpClient`): Ktor client,
  with OkHttp (Android) / Darwin (iOS) engines via expect/actual.
- **Koin modules** (`di/`): one `val xModule = module { ... }` per concern
  (`CommonModule`, `DatabaseModule`, `NetworkModule`, `AndroidLocationModule`,
  `IosLocationModule`, etc.). Android- and iOS-specific modules live in
  `androidMain`/`iosMain` respectively; `shared` assembles all of them.
- **Platform abstractions** (`common/`): `expect`/`actual` for
  `KeyValueStorage` (SharedPreferences vs NSUserDefaults), `PlatformHttpClient`
  engine, logger creation, `DatabaseBuilder`.
- **Location & tracking** (`location/`, `tracking/`): Android's
  `AndroidLocationRepositoryImpl` (FusedLocationProviderClient, callback-
  based) vs iOS's `IosLocationRepositoryImpl` (CoreLocation, delegate-based
  via the composition pattern — Kotlin/Native forbids mixing Kotlin and
  Objective-C supertypes directly). `AndroidTrackingServiceLauncher` starts
  a real foreground Service; `IosTrackingServiceLauncher` toggles CoreLocation
  background updates directly, since iOS has no foreground-service concept.

## What does NOT belong here

- Business rules that don't need a repository (put those in `domain`'s use
  cases).
- UI-facing error models (`RouteUiError` lives in `core`) — `data` throws/
  returns `domain`'s `RouteError`, never a UI-shaped type.
- Compose or SwiftUI code of any kind.

## Dependencies

`data` depends on `domain` (as `api`, so `shared` can re-export it
transitively to Swift).

## Extending this module

New repository: define the interface in `domain/repository/`, implement it
here, register it in the matching Koin module in `di/`. If the
implementation needs platform-specific behavior, use `expect`/`actual` —
never `if (Platform.isAndroid)` branching inside shared code.

Kotlin/Native has no reflection: no MockK in `commonTest` (see `domain`'s
README for the same rule) and Room requires the `@ConstructedBy` mechanism
for its expect/actual database constructor. `androidHostTest` is reserved
for tests that genuinely require Robolectric/JVM Android simulation
(currently only `UserProfileRepositoryImplTest`); everything else that can
run via `commonTest` + `kotlin.test` should.
