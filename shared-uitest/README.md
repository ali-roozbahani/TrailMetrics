# shared-uitest

Test-only KMP module. It builds a **test-only variant** of
`TrailMetricsShared.xcframework` for the iOS UI tests: the same Swift module
as `shared`'s framework, with the same API plus the UI-test seam of this
module. Targets: `iosArm64`, `iosSimulatorArm64` (no Android, no JVM).

`shared` stays the only module that exports production API to iOS;
`shared-uitest` builds only a test-only variant of the same framework, linked
by UI-test builds alone (`docs/architecture/ADR-002-shared-umbrella-module.md`,
"Amendment"). No production module depends on this one.

## What lives here

Package `dev.roozbahani.trailmetrics.uitest`, in `src/iosMain`:

- **`UiTestEntry.kt`**: `doInitKoinIosForUiTest(scenario)`, the UI-test
  counterpart of `doInitKoinIos()`. It calls `initKoin()` and then
  `loadKoinModules(...)` with the override module, never
  `initKoin { modules(...) }`, whose modules the production modules would
  replace again.
- **`UiTestScenario.kt`**: the scripted situations (`FailedDelete`,
  `DeleteTwice`, `GenerateTwice`, `GenerateThenReset`, `FinishTwice`).
- **`UiTestControls.kt`**: the counters a UI test reads (directions
  requests and completions, saves, deletes) and `releaseHeldCalls()`.
- **`UiTestFakes.kt`**, **`UiTestFixtures.kt`**, **`UiTestModule.kt`**
  (`internal`): in-memory fakes of `LocationRepository`,
  `TrackingServiceLauncher`, `DirectionsRepository`,
  `ActivityHistoryRepository` and `UserProfileRepository`, their fixed data,
  and the Koin module that binds them.

Swift sees exactly `doInitKoinIosForUiTest(scenario:)`, `UiTestScenario` and
`UiTestControls` (plain, non-suspend members); everything else is
`internal`. No `suspend` function and no `Flow` is visible to Swift.

The tests in `src/iosTest` (`kotlin.test`) run with
`./gradlew :shared-uitest:iosSimulatorArm64Test`, and in the gate's
`allTests`.

## Build

`./gradlew :shared-uitest:assembleTrailMetricsSharedDebugXCFramework` writes
the variant to `shared-uitest/build/XCFrameworks/debug/`. Don't copy it by
hand: `scripts/build-kmp-framework.sh --variant uitest` builds it, checks
that its API is production's plus this module's declarations, and copies it
over `shared/build/XCFrameworks/debug/TrailMetricsShared.xcframework`, so
`SharedKit/Package.swift` does not change. The next run without
`--variant uitest` puts the production framework back. Normal Debug and
Release builds never link the variant. The Xcode configuration
`Debug-UITest` and its scheme `TrailMetricsUITests` link it, and the Swift
call site that enters the seam is `TrailMetricsApp.init()`, under
`#if UITEST_SEAM`, when a UI test passes `-uiTestScenario <name>`.

No Kover and no coverage floor: Kover can't measure iOS-only code, so the
build file does not read `config/kover-floors.properties` (like `shared`).
