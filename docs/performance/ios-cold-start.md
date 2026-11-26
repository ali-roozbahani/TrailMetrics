# iOS cold start: `cold_start_first_frame_ms`

**Simulator numbers.** They describe this code on a simulator on a Mac, not what an iPhone does.

## Result (2026-11-26, baseline)

| Metric | Median | Range | Runs |
|---|---|---|---|
| `cold_start_first_frame_ms` (XCTest `Duration (AppLaunch)`) | **1002 ms** (series 1), 996 ms (series 2) | 954 to 1092 ms; 953 to 1668 ms | 2 series of 20 |
| `CrashReportingStart` interval | 2.75 ms, 2.69 ms | 2.52 to 3.93 ms | same |
| `KoinStart` interval | 0.66 ms, 0.69 ms | 0.60 to 0.92 ms | same |
| `MapsConfigure` interval | 0.06 ms, 0.06 ms | 0.05 to 0.10 ms | same |

The baseline of `cold_start_first_frame_ms` on this setup is **1002 ms**, the median of the first series.

Noise: the two series' medians differ by 0.6%. Series 2's first two launches (1668 ms and 1178 ms) are its
outliers; without them its range is 953 to 1053 ms. One comparison of two series is not yet a noise model: the
budget's 10% is well above the 0.6% seen here, but more series are needed before a gate (`README.md`).

What the numbers say: the three named phases in `TrailMetricsApp.init` together take under 4 ms of the
roughly 1000 ms. The rest is before `init` (process start, loading the app's frameworks, the Kotlin
framework among them) and after it (the first SwiftUI frame). No phase is marked there yet, so this file
makes no claim about where in it the time goes.

## Setup

- Simulator: `TrailMetrics_UITest` (iPhone 17, iOS 26.5, build 23F77), the pinned simulator of
  `scripts/ios-ui-tests.sh`, erased and booted before each series.
- Host: Mac with Apple M4, 16 GB, macOS 27.2.1; Xcode 27.2 (27B52).
- Build: configuration **Release** of the app and the UI-test target, code coverage off, simulator arm64.
  Not what users run, in three ways:
  - The Release build links the **debug** Kotlin framework (`release-build-links-debug-xcframework`): a
    larger, unoptimised framework, which likely makes the launch slower than a release framework would.
  - No `GoogleService-Info.plist` was in the app, so crash reporting was not started
    (`CrashReporting.startIfConfigured` returned at once): a build with it pays Firebase's start in
    `CrashReportingStart`.
  - Whether the build had a Maps key was not checked (the agent does not read `Secrets.xcconfig`); the
    launch does not wait for the map either way.
- Metric: `XCTApplicationLaunchMetric()` (launch until the app's first frame), with
  `XCTOSSignpostMetric` for the app's `os_signpost` intervals (`StartupSignposts`, subsystem
  `dev.roozbahani.TrailMetrics`, category `Startup`). The series were taken at commit 6eafb89, where the subsystem was
  spelled `dev.roozbahani.trailmetrics`; the spelling was then aligned with the app's other logger, nothing else
  changed. Each iteration calls `XCUIApplication().launch()`,
  which terminates the instance of the iteration before.

## How to measure again

Shut down and erase the pinned simulator, boot it, then from `iosApp/` (through `scripts/heavy-run.sh`):

```bash
TEST_RUNNER_TM_LAUNCH_ITERATIONS=20 xcodebuild test -project TrailMetrics.xcodeproj \
  -scheme TrailMetricsUITests -configuration Release \
  -destination "platform=iOS Simulator,id=<TrailMetrics_UITest id>" -skipMacroValidation \
  -only-testing:TrailMetricsUITests/LaunchPerformanceTests \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 EXCLUDED_ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
  -enableCodeCoverage NO 2>&1 | ../scripts/filter-xcode-log.sh
```

`TEST_RUNNER_` variables reach the test only through xcodebuild's environment, not as a build setting
argument. The values are the `measured [Duration (...), s]` lines of the log. The gate's UI run also runs
`LaunchPerformanceTests` (5 iterations, configuration Debug-UITest, never failing on time): its numbers are
not comparable with these (another configuration and framework variant).
