# shared

KMP umbrella module. This is the **only** module responsible for
cross-platform dependency-injection composition and for exporting
production Kotlin API to iOS. Targets: `android`, `iosArm64`,
`iosSimulatorArm64`.

`shared` stays the only module that exports production API to iOS;
`shared-uitest` builds only a test-only variant of the same framework,
linked by UI-test builds alone (`docs/architecture/ADR-002-shared-umbrella-module.md`,
"Amendment"). That variant is `shared`'s framework plus the iOS UI-test
seam; `shared` never depends on `shared-uitest`, and nothing UI-test related
belongs here.

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
  The only other module that applies SKIE and defines a framework is the
  test-only `shared-uitest` (see above).

- **Tests** (`commonTest`, `androidHostTest`, `iosTest`): `KoinGraphAndroidTest` and
  `KoinGraphIosTest` start the graph `initKoin` builds, replace the platform pieces that need a
  `Context` or a device with fakes, and resolve every definition, so a missing binding fails here and
  not at app start.

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
  automatically via `scripts/build-kmp-framework.sh`, which the Xcode
  `TrailMetrics` scheme's Build pre-action and the "Build KMP Shared
  Framework" phase run (see `.claude/skills/tm-ios` → "Build integration");
  when working from the command line, run that script (or
  `./gradlew :shared:assembleTrailMetricsSharedDebugXCFramework`) manually.
  `scripts/build-kmp-framework.sh --variant uitest` puts the test-only
  variant at this module's debug path
  (`shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework`) instead;
  the next run without it puts this module's framework back. Normal Debug
  and Release builds never link the variant.
