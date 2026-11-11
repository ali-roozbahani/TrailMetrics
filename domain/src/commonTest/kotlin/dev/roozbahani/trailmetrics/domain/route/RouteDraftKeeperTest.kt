package dev.roozbahani.trailmetrics.domain.route

import dev.roozbahani.trailmetrics.domain.fakes.FakeLogger
import dev.roozbahani.trailmetrics.domain.fakes.FakeRouteDraftStore
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RouteDraftKeeperTest {

    private val testScheduler = TestCoroutineScheduler()
    private val store = FakeRouteDraftStore()
    private val keeper = RouteDraftKeeper(
        RouteDraftSaver(store, FakeLogger(), TestScope(StandardTestDispatcher(testScheduler)))
    )

    @Test
    fun `nothing is written before the plan is kept`() = runTest(testScheduler) {
        keeper.save(draftA)
        testScheduler.runCurrent()

        assertEquals(emptyList(), store.writes)
    }

    @Test
    fun `a user change keeps the plan and later saves are written`() = runTest(testScheduler) {
        keeper.onUserChange()
        keeper.save(draftA)
        testScheduler.runCurrent()

        assertEquals(listOf<StoredRouteDraft?>(draftA), store.writes)
    }

    @Test
    fun `a loaded plan is not kept until the screen keeps it`() = runTest(testScheduler) {
        store.stored = draftA

        assertEquals(draftA, keeper.loadStoredPlan())
        keeper.save(draftB)
        testScheduler.runCurrent()

        assertEquals(emptyList(), store.writes, "a save between the load and keeping the plan was written")
    }

    @Test
    fun `a kept restored plan is written from then on`() = runTest(testScheduler) {
        store.stored = draftA

        assertEquals(draftA, keeper.loadStoredPlan())
        assertTrue(keeper.keepRestoredPlan())
        keeper.save(draftB)
        testScheduler.runCurrent()

        assertEquals(listOf<StoredRouteDraft?>(draftB), store.writes)
    }

    @Test
    fun `a user change before the load returns drops the loaded plan`() = runTest(testScheduler) {
        store.stored = draftA

        keeper.onUserChange()

        assertNull(keeper.loadStoredPlan())
    }

    @Test
    fun `a user change between the load and keeping it drops the loaded plan`() = runTest(testScheduler) {
        store.stored = draftA
        assertEquals(draftA, keeper.loadStoredPlan())

        keeper.onUserChange()

        assertFalse(keeper.keepRestoredPlan())
    }

    @Test
    fun `nothing stored or a failing read does not keep the plan`() = runTest(testScheduler) {
        assertNull(keeper.loadStoredPlan())
        store.stored = draftA
        store.loadFailure = IllegalStateException("corrupt row")
        assertNull(keeper.loadStoredPlan())

        keeper.save(draftB)
        testScheduler.runCurrent()

        assertEquals(emptyList(), store.writes)
        assertEquals(draftA, store.stored)
    }

    @Test
    fun `clear is written whether or not the plan is kept`() = runTest(testScheduler) {
        store.stored = draftA

        keeper.clear()
        testScheduler.runCurrent()

        assertNull(store.stored)
    }

    private companion object {
        val draftA = StoredRouteDraft(
            Coordinates(51.336, 12.388),
            listOf(RoutePoint(Coordinates(51.337, 12.389), 0)),
            null,
            ActivityType.Running
        )
        val draftB = draftA.copy(activityType = ActivityType.Cycling)
    }
}
