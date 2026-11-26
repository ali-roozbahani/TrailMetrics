package dev.roozbahani.trailmetrics.benchmark

import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.StartupMode
import androidx.benchmark.macro.StartupTimingMetric
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * `cold_start_first_frame_ms` of docs/performance/: the app's process is killed before each iteration, the
 * launcher intent starts it, and [StartupTimingMetric] reports `timeToInitialDisplayMs` (the first frame).
 * The app has no fully-drawn point (no `reportFullyDrawn`), so there is no `timeToFullDisplayMs`.
 *
 * [CompilationMode.None]: no ahead-of-time compilation and no baseline profile (the app has none), the state of
 * a fresh install before the system compiles it in the background.
 */
@RunWith(AndroidJUnit4::class)
class ColdStartBenchmark {

    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    @Test
    fun coldStartToFirstFrame() = benchmarkRule.measureRepeated(
        packageName = TARGET_PACKAGE,
        metrics = listOf(StartupTimingMetric()),
        iterations = ITERATIONS,
        startupMode = StartupMode.COLD,
        compilationMode = CompilationMode.None(),
    ) {
        pressHome()
        startActivityAndWait()
    }

    private companion object {
        const val TARGET_PACKAGE = "dev.roozbahani.trailmetrics"
        const val ITERATIONS = 20
    }
}
