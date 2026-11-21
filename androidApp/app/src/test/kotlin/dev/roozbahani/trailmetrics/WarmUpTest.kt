@file:OptIn(ExperimentalCoroutinesApi::class) // the test dispatchers have no stable replacement

package dev.roozbahani.trailmetrics

import dev.roozbahani.trailmetrics.core.testing.FakeLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WarmUpTest {

    @Test
    fun `the build runs on the injected dispatcher and not on the caller`() = runTest {
        var builds = 0
        // The caller's scope runs a launch at once, so a build that did not leave it would have run by now.
        val caller = CoroutineScope(UnconfinedTestDispatcher(testScheduler))
        val job = warmUp(caller, StandardTestDispatcher(testScheduler), FakeLogger()) { builds++ }

        assertEquals(0, builds, "the build ran on the caller's thread")
        testScheduler.runCurrent()
        job.join()
        assertEquals(1, builds)
    }

    @Test
    fun `a failing build is logged and does not end the scope`() = runTest {
        val logger = FakeLogger()
        val scope = CoroutineScope(UnconfinedTestDispatcher(testScheduler))

        val job = warmUp(scope, StandardTestDispatcher(testScheduler), logger) { error("no database") }
        testScheduler.runCurrent()
        job.join()

        assertTrue(job.isCompleted && !job.isCancelled)
        assertFalse(logger.messages.isEmpty(), "the failure was not logged")
    }
}
