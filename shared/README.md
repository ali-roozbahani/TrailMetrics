# shared

KMP umbrella module. This is the **only** module responsible for
cross-platform dependency-injection composition and for exporting Kotlin
code to iOS. Targets: `android`, `iosArm64`, `iosSimulatorArm64`.

## What lives here

- **`di/KoinInit.kt`** (`commonMain`): `expect val platformModules: List<Module>`
  plus `fun initKoin(appDeclaration: KoinAppDeclaration = {})`, which starts
  Koin with the shared modules from `data`/`domain` plus whatever
  `platformModules` resolves to on each platform. This is the single entry
  point every platform's composition root calls into.
- **`di/PlatformModules.android.kt`** / **`PlatformModules.ios.kt`**: the
  `actual` list of platform-specific Koin modules (`AndroidCommonModule`,
  `AndroidLocationModule`, `AndroidTrackingModule` on Android;
  `IosCommonModule`, `IosLocationModule` on iOS).
- **`di/KoinInitIos.kt`** (`iosMain`): `fun doInitKoinIos()` — the no-argument
  wrapper Swift actually calls from `TrailMetricsApp.init()`.
- **`di/KoinHelper.kt`** (`iosMain`): a `KoinComponent` bridge class exposing
  concrete getter functions (e.g. `getActivityHistoryRepository()`). Needed
  because Koin's `get<T>()` is an inline reified function and cannot be
  exported to Objective-C/Swift — add a new getter here whenever a new iOS
  feature needs to resolve a dependency from Koin.
- **XCFramework export config**: the `binaries.framework { ... }` block that
  produces `TrailMetricsShared.xcframework`, `export()`-ing `domain`, `data`,
  and `core` so their public API is visible from Swift. SKIE
  (`co.touchlab.skie`) is applied here (and only here) to make Kotlin
  `Flow`/suspend functions usable from Swift as `AsyncSequence`/`async`.

## What does NOT belong here

- Business logic (goes in `domain`), repository implementations (`data`),
  or shared models/navigation (`core`) — `shared` only wires things
  together and exports them.
- Android-only Compose UI Koin modules (e.g. `routeModule`,
  `trackingUiModule`, `historyUiModule`, which provide ViewModels) — those
  are passed into `initKoin { modules(...) }` from `androidApp/app`'s
  `Application` class directly, since `shared` has no knowledge of
  `androidApp/feature-*`.

## Dependencies

`shared` depends on (and exports) `domain`, `data`, and `core`, all as
`api(...)` — required for `export()` to work; `implementation(...)` would
hide their symbols from the generated Swift interface.

## Extending this module

- New Android or iOS Koin module in `data`/`domain`? Add it to the relevant
  `PlatformModules.<platform>.kt` list (or to `initKoin`'s shared
  `modules(...)` call if it's truly cross-platform) so it actually gets
  registered.
- New iOS feature needs a dependency from Koin? Add a getter to
  `KoinHelper.kt` — don't try to call `get<T>()` directly from Swift, it
  won't compile.
- After any change to `domain`, `data`, `core`, or `shared` itself, the
  XCFramework must be rebuilt. In day-to-day iOS development this happens
  automatically via the Xcode Run Script build phase (see
  `docs/architecture/OVERVIEW.md` → "iOS build integration"); when working
  from the command line, run
  `./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework` manually.
