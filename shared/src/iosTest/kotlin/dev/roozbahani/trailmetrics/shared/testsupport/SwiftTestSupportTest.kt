package dev.roozbahani.trailmetrics.shared.testsupport

import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertSame
import kotlin.test.assertTrue

class SwiftTestSupportTest {

    @Test
    fun `SwiftTestFlow emits its values in order and completes`() = runTest {
        val flow = SwiftTestFlow(listOf("a", "b", "c"))

        assertEquals(listOf("a", "b", "c"), flow.toList())
    }

    @Test
    fun `SwiftTestFlow restarts for every collector`() = runTest {
        val flow = SwiftTestFlow(listOf(1, 2))

        assertEquals(listOf(1, 2), flow.toList())
        assertEquals(listOf(1, 2), flow.toList())
    }

    @Test
    fun `SwiftTestScope cancel cancels its running coroutines`() {
        val scope = SwiftTestScope()
        val job = scope.launch { awaitCancellation() }

        scope.cancel()

        assertTrue(job.isCancelled)
    }

    @Test
    fun `SwiftTestResult success boxes a Result holding the value`() {
        val boxed = SwiftTestResult.success("value")

        val result = assertIs<Result<*>>(boxed)
        assertEquals("value", result.getOrThrow())
    }

    @Test
    fun `SwiftTestResult failure boxes a Result that rethrows the exception`() {
        val exception = IllegalStateException("boom")

        val result = assertIs<Result<*>>(SwiftTestResult.failure(exception))

        assertSame(exception, assertFailsWith<IllegalStateException> { result.getOrThrow() })
    }
}
