@file:OptIn(ExperimentalCoroutinesApi::class) // the test dispatchers have no stable replacement

package dev.roozbahani.trailmetrics.data.tracking

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class OffMainLazyTest {

    @Test
    fun `the first get builds the value on the injected dispatcher, not on the caller's`() = runTest {
        var builds = 0
        val offMain = OffMainLazy(lazy { ++builds }, StandardTestDispatcher(testScheduler))

        val call = backgroundScope.async(UnconfinedTestDispatcher(testScheduler)) { offMain.get() }

        assertEquals(0, builds, "the value was built on the caller's dispatcher")
        assertFalse(call.isCompleted)
        testScheduler.runCurrent()
        assertEquals(1, call.await())
        assertEquals(1, builds)
    }

    @Test
    fun `a value that exists is returned without a switch`() = runTest {
        val built = lazy { "manager" }
        built.value
        // A queued dispatcher that nobody runs: a get that switched to it would never complete.
        val offMain = OffMainLazy(built, StandardTestDispatcher(testScheduler))

        val call = backgroundScope.async(UnconfinedTestDispatcher(testScheduler)) { offMain.get() }

        assertTrue(call.isCompleted, "get switched dispatchers for a value that was already built")
        assertEquals("manager", call.await())
    }
}
