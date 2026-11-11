package dev.roozbahani.trailmetrics.domain.route

import dev.roozbahani.trailmetrics.domain.fakes.FakeLogger
import dev.roozbahani.trailmetrics.domain.fakes.FakeRouteDraftStore
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RouteDraftSaverTest {

    private val testScheduler = TestCoroutineScheduler()
    private val writerScope = TestScope(StandardTestDispatcher(testScheduler))
    private val store = FakeRouteDraftStore()
    private val logger = FakeLogger()
    private val saver = RouteDraftSaver(store, logger, writerScope)

    @Test
    fun `save writes the draft in the writer scope and not in the caller`() = runTest(testScheduler) {
        saver.save(draftA)

        assertEquals(emptyList(), store.writes)
        testScheduler.runCurrent()
        assertEquals(listOf<StoredRouteDraft?>(draftA), store.writes)
        assertEquals(draftA, store.stored)
    }

    @Test
    fun `clear clears the store`() = runTest(testScheduler) {
        store.stored = draftA

        saver.clear()
        testScheduler.runCurrent()

        assertNull(store.stored)
        assertEquals(listOf<StoredRouteDraft?>(null), store.writes)
    }

    @Test
    fun `requests made while a write runs are not queued and only the newest is written`() = runTest(testScheduler) {
        val gate = CompletableDeferred<Unit>()
        store.writeGate = gate
        saver.save(draftA)
        testScheduler.runCurrent()

        saver.save(draftB)
        saver.save(draftC)
        gate.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(listOf<StoredRouteDraft?>(draftA, draftC), store.writes)
        assertEquals(draftC, store.stored)
    }

    @Test
    fun `a clear requested after a save wins over that save`() = runTest(testScheduler) {
        val gate = CompletableDeferred<Unit>()
        store.writeGate = gate
        saver.save(draftA)
        testScheduler.runCurrent()

        saver.save(draftB)
        saver.clear()
        gate.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(listOf(draftA, null), store.writes)
        assertNull(store.stored)
    }

    @Test
    fun `the same draft saved again after a clear is written again`() = runTest(testScheduler) {
        saver.save(draftA)
        testScheduler.runCurrent()
        saver.clear()
        testScheduler.runCurrent()

        saver.save(draftA)
        testScheduler.runCurrent()

        assertEquals(listOf(draftA, null, draftA), store.writes)
    }

    @Test
    fun `a failing save is logged and the next save is written`() = runTest(testScheduler) {
        store.saveFailure = IllegalStateException("disk full")
        saver.save(draftA)
        testScheduler.runCurrent()

        store.saveFailure = null
        saver.save(draftB)
        testScheduler.runCurrent()

        assertEquals(listOf<StoredRouteDraft?>(draftB), store.writes)
        assertTrue(logger.loggedMessages.single().second.contains("disk full"))
    }

    @Test
    fun `restore returns the stored draft`() = runTest(testScheduler) {
        store.stored = draftB

        assertEquals(draftB, saver.restore())
    }

    @Test
    fun `restore returns null when nothing is stored`() = runTest(testScheduler) {
        assertNull(saver.restore())
        assertTrue(logger.loggedMessages.isEmpty())
    }

    @Test
    fun `a failing restore returns null and logs and keeps the stored draft`() = runTest(testScheduler) {
        store.stored = draftA
        store.loadFailure = IllegalStateException("corrupt row")

        assertNull(saver.restore())

        assertTrue(logger.loggedMessages.single().second.contains("corrupt row"))
        assertEquals(draftA, store.stored)
        assertEquals(emptyList(), store.writes)
    }

    private companion object {
        val START = Coordinates(51.336, 12.388)
        val draftA =
            StoredRouteDraft(START, listOf(RoutePoint(Coordinates(51.337, 12.389), 0)), null, ActivityType.Running)
        val draftB = draftA.copy(activityType = ActivityType.Cycling)
        val draftC = draftA.copy(activityType = ActivityType.Walking)
    }
}
