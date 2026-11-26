# androidApp/benchmark

Test-only `com.android.test` module: the Macrobenchmark of the app's cold start (`ColdStartBenchmark`,
metric `cold_start_first_frame_ms` of `docs/performance/README.md`). It measures the app's `benchmark`
build type (the release build type, debug-signed and profileable) and ships nothing in the app.

The gate and CI compile its debug variant (`assembleDebug`); neither runs it. The `benchmark` variant that a
measurement installs is built by `connectedBenchmarkAndroidTest`; the gate and CI do not build it. A measurement runs it on a device or on the gate's emulator,
and records its numbers as `docs/performance/android-cold-start.md` says.
