package dev.roozbahani.trailmetrics.shared.crash

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** What an uncaught Kotlin exception becomes for the crash reporting adapter. */
class FatalKotlinExceptionReportingTest {

    private class TrackFailure(message: String?, cause: Throwable? = null) : IllegalStateException(message, cause)

    private class LoopingFailure : IllegalStateException("loop") {
        var next: Throwable? = null
        override val cause: Throwable? get() = next
    }

    private fun thrown(block: () -> Nothing): Throwable =
        try {
            block()
        } catch (expected: IllegalStateException) {
            expected
        }

    @Test
    fun theNameIsTheQualifiedClassNameAndTheReasonTheMessage() {
        val reported = thrown { throw TrackFailure("boom") }.toReportedKotlinException()

        assertEquals(
            "dev.roozbahani.trailmetrics.shared.crash.FatalKotlinExceptionReportingTest.TrackFailure",
            reported.name,
        )
        assertEquals("boom", reported.reason)
    }

    @Test
    fun theReasonListsEveryCauseWithItsClassAndMessage() {
        val root = IllegalArgumentException("bad input")
        val middle = TrackFailure(null, root)
        val reported = thrown { throw TrackFailure("outer", middle) }.toReportedKotlinException()

        assertEquals(
            "outer" +
                "\nCaused by: dev.roozbahani.trailmetrics.shared.crash.FatalKotlinExceptionReportingTest.TrackFailure" +
                "\nCaused by: kotlin.IllegalArgumentException: bad input",
            reported.reason,
        )
    }

    @Test
    fun aMissingMessageGivesAnEmptyReason() {
        assertEquals("", thrown { throw TrackFailure(null) }.toReportedKotlinException().reason)
    }

    @Test
    fun theStackHoldsTheThrowSitesReturnAddresses() {
        val reported = thrown { throw TrackFailure("boom") }.toReportedKotlinException()

        assertTrue(reported.stackAddresses.isNotEmpty())
        assertTrue(reported.stackAddresses.all { it != 0L })
    }

    @Test
    fun aCauseChainThatLoopsStopsAfterTenCauses() {
        val first = LoopingFailure()
        val second = LoopingFailure().apply { next = first }
        first.next = second

        val reported = first.toReportedKotlinException()

        assertEquals(10, reported.reason.lines().count { it.startsWith("Caused by: ") })
    }
}
