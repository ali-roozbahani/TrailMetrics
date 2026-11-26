# Performance budget

Owner decisions of 2026-11-26. A performance claim without a number is not accepted: a statement that
something is faster or slower names the measurement (a file under `docs/performance/`) it comes from.

## The budget

- **Baseline.** The first recorded measurement of a metric on a setup is its baseline. A setup is the
  device or emulator or simulator, the OS version and the build type; two numbers are compared only when
  their setups are the same.
- **Budget.** Until the owner sets absolute targets, the budget of every metric is: **no regression of more
  than 10% from the baseline**, compared on the median of the runs.
- **No CI gate yet.** Nothing checks the budget automatically. The first measurements also record how noisy
  each one is (the spread of its runs, and the change between two series on the same setup); a gate is
  designed only once that is known.
- **Emulator and simulator numbers are labeled as such.** They describe the code on that setup, not what a
  user's phone does; a number from a real device says so too.

## Metrics

The same names on both platforms. Each measurement file states the metric's name, the tool, the setup, the
build and the number of runs.

| Metric | What it measures | Android | iOS |
|---|---|---|---|
| `cold_start_first_frame_ms` | Process not running; launch from the launcher until the app's first frame is drawn. | Macrobenchmark `StartupTimingMetric`, `timeToInitialDisplayMs`, `StartupMode.COLD` | XCTest `XCTApplicationLaunchMetric` (launch duration to the first frame) |
| `cold_start_fully_drawn_ms` | As above, until a defined fully-drawn point. Neither app defines one today, so it is not measured. | `timeToFullDisplayMs` once the app calls `reportFullyDrawn` | an `os_signpost` interval ending at the same point |
| `first_map_frame_ms` | Launch until the Route screen's map draws its first frame. | a trace section ended by the map's loaded callback | an `os_signpost` interval ended by the map's first render |
| `history_scroll_jank_pct` | Share of frames that missed their deadline during a scripted fling over a seeded History list. | Macrobenchmark `FrameTimingMetric` (frames with `frameOverrunMs` > 0, divided by all frames) | XCTest's scrolling `XCTOSSignpostMetric` (hitch count divided by frame count) |
| `tracking_2h_memory_mb` | Resident memory of the app during a 2-hour tracking session with a fake location feed: peak and at the end. | `dumpsys meminfo` total PSS, sampled | `XCTMemoryMetric` / physical footprint, sampled |
| `tracking_2h_cpu_pct` | Average CPU of the app's process over the same session, in percent of one core. | `/proc/<pid>/stat` CPU time over wall time | `XCTCPUMetric` |
| `alloc_per_location_update_bytes` | Bytes allocated on the path from one location update to the emitted tracking state, averaged over a steady run of updates. | allocation tracking over a counted run of updates | Instruments Allocations over a counted run of updates |

## Baselines

| Metric | Android | iOS |
|---|---|---|
| `cold_start_first_frame_ms` | not measured yet | not measured yet |
| `cold_start_fully_drawn_ms` | not defined (no fully-drawn point) | not defined (no fully-drawn point) |
| `first_map_frame_ms` | not measured yet | not measured yet |
| `history_scroll_jank_pct` | not measured yet | not measured yet |
| `tracking_2h_memory_mb` | not measured yet | not measured yet |
| `tracking_2h_cpu_pct` | not measured yet | not measured yet |
| `alloc_per_location_update_bytes` | not measured yet | not measured yet |

A cell gets the median, the setup and a link to its measurement file when the first measurement lands. The
metrics still "not measured" are the board epic `performance-baseline-remaining-metrics`.

## Known data from outside this folder

- Firebase Crashlytics' initialisation blocked the main thread in `Application.onCreate` for 108 ms on the
  app's first start and 20 ms on later starts (Android; a datum given by the owner on 2026-11-26, its setup
  not recorded here). Crashlytics runs only in a build that has the owner's `google-services.json`
  (`androidApp/app/build.gradle.kts`), so a measurement states whether its build had it.
