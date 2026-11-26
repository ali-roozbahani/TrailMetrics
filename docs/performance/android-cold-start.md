# Android cold start: `cold_start_first_frame_ms`

**Emulator numbers.** They describe this code on an emulator on a Mac, not what a phone does.

## Result (2026-11-26, baseline)

| Series | Settle after boot | Median `timeToInitialDisplayMs` | Range | Values |
|---|---|---|---|---|
| 1 (not used) | 20 s | 1100 ms | 680 to 2035 ms | 20 of 20 |
| **2 (baseline)** | 180 s | **852 ms** | 597 to 999 ms | 20 of 20 |
| 3 | 180 s | 901 ms | 665 to 1169 ms | 19 of 20 |

The baseline of `cold_start_first_frame_ms` on this setup is **852 ms**, the median of series 2, the first
series taken with the method below.

- Series 1 is not used: 20 s after the boot of a freshly wiped image, the system was still busy with its
  first-boot work, and its runs spread over a factor of three. Waiting 180 s (series 2 and 3) narrowed them.
- Noise: series 3's median is 5.8% above series 2's on the same setup and method. On this emulator that is
  more than half of the budget's 10%, so a single series cannot tell a 10% regression from noise; a gate
  would need several series per side (`README.md`, "No CI gate yet").
- One iteration of series 3 gave no `timeToInitialDisplayMs` (Macrobenchmark recorded its trace but no
  value), so its median is over 19 values.
- `cold_start_fully_drawn_ms` is not measured: the app calls no `reportFullyDrawn`, so there is no
  `timeToFullDisplayMs`.

## Setup

- Emulator: the gate's dedicated AVD `TrailMetrics_UITest` (`scripts/android-ui-tests.sh`): image
  `system-images/android-37.1/google_apis_playstore_ps16k/arm64-v8a`, API 37 (Android 17, build
  CP31.260623.005), 4 cores, 4 GB RAM, emulator 36.6.11.0, started headless with `-wipe-data -no-snapshot` on
  port 5560 for each series. CPU clocks not locked (an emulator cannot lock them).
- Host: Mac with Apple M4, 16 GB, macOS 27.2.1.
- Build: the app's **`benchmark`** build type: the `release` build type as it is today (R8 off, no keep rules,
  `isDebuggable = false`), signed with the debug key so it installs, profileable, and with crash reporting
  collection off. The series were measured before that last setting was added; in a build without
  `google-services.json` it changes only a manifest value that nothing reads, since no Firebase app starts. What it is not:
  - Not minified. No minified release build exists yet (`android-first-minified-release-build`); the first
    one is a new setup with its own baseline, and it is the one that represents what users will run.
  - No `google-services.json`, so no Firebase app was initialised: the measured start contains no
    Crashlytics. With the file, the `benchmark` build type still has Crashlytics' collection off
    (`crashReportingEnabled = false`, so a benchmark run never reports); its start is then still not the
    release build's. The owner's datum (Crashlytics blocked the main thread 108 ms on the first start, 20 ms
    later, `README.md`) is the cost a build with it adds in `Application.onCreate`.
  - No baseline profile (`android-baseline-profiles-and-macrobenchmark`), and measured with
    `CompilationMode.None()`: no ahead-of-time compilation, as a fresh install before the system compiles it.
  - Whether the build had a Maps key was not checked (the agent does not read `local.properties`); the
    first frame does not wait for map tiles.
- Benchmark: `androidApp/benchmark`, `ColdStartBenchmark.coldStartToFirstFrame`: Macrobenchmark 1.5.0,
  `StartupTimingMetric`, `StartupMode.COLD` (the process is killed before each iteration), launcher intent
  after `pressHome()`, 20 iterations. Macrobenchmark's emulator check is suppressed
  (`androidx.benchmark.suppressErrors=EMULATOR`) and it labels the output "Running on Emulator".

## How to measure again

Start the AVD as `scripts/android-ui-tests.sh` does (`emulator -avd TrailMetrics_UITest -port 5560 -no-window
-no-audio -no-snapshot -wipe-data -no-boot-anim`), wait for `sys.boot_completed`, then 180 s more, and run
through `scripts/heavy-run.sh` with `ANDROID_SERIAL=emulator-5560`:

```bash
./gradlew :androidApp:benchmark:connectedBenchmarkAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.androidx.benchmark.suppressErrors=EMULATOR
```

The result is in
`androidApp/benchmark/build/outputs/connected_android_test_additional_output/benchmark/connected/<device>/`
(`*-benchmarkData.json`: `metrics.timeToInitialDisplayMs`, with each iteration's value under `runs`, and one
Perfetto trace per iteration). On a real device drop the `suppressErrors` argument.
