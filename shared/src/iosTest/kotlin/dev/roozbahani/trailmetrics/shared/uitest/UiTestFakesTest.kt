package dev.roozbahani.trailmetrics.shared.uitest

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.koin.core.context.stopKoin
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class UiTestFakesTest {

    @AfterTest
    fun tearDown() {
        stopKoin()
    }

    @Test
    fun `saves and deletes update observeActivities and getActivity`() = runTest {
        UiTestScenario.entries.filterNot { it.failsDelete }.forEach { scenario ->
            val launch = launchUiTest(scenario)
            launch.controls.releaseHeldCalls()
            val initial = initialHistory(scenario)
            val emissions = mutableListOf<List<ActivityRecord>>()
            val collector = backgroundScope.launch { launch.history.observeActivities().toList(emissions) }
            testScheduler.runCurrent()
            assertEquals(listOf(initial), emissions, "$scenario: first emission")

            val id = launch.history.saveActivity(newActivity)
            val saved = newActivity.copy(id = id)
            testScheduler.runCurrent()
            assertEquals(initial.size + 1L, id, "$scenario: next id")
            assertEquals(initial + saved, emissions.last(), "$scenario: after the save")
            assertEquals(saved, launch.history.getActivity(id), "$scenario: getActivity after the save")

            launch.history.deleteActivity(id)
            testScheduler.runCurrent()
            assertEquals(initial, emissions.last(), "$scenario: after the delete")
            assertNull(launch.history.getActivity(id), "$scenario: getActivity after the delete")
            assertEquals(listOf(0, 0, 1, 1), launch.controls.counters(), "$scenario: counters")
            collector.cancel()
            stopKoin()
        }
    }

    @Test
    fun `a held call completes only after release and later calls do not wait`() = runTest {
        UiTestScenario.entries.forEach { scenario ->
            val heldCall = scenario.heldCall ?: return@forEach
            val launch = launchUiTest(scenario)

            val held = startCall(heldCall, launch.history, launch.directions)
            testScheduler.runCurrent()
            assertFalse(held.isCompleted, "$scenario: $heldCall completed while held")

            launch.controls.releaseHeldCalls()
            testScheduler.runCurrent()
            assertTrue(held.isCompleted, "$scenario: $heldCall still waiting after release")
            assertTrue(held.await().isSuccess, "$scenario: $heldCall failed")

            val later = startCall(heldCall, launch.history, launch.directions)
            testScheduler.runCurrent()
            assertTrue(later.isCompleted, "$scenario: $heldCall after release waited")
            stopKoin()
        }
    }

    @Test
    fun `calls a scenario does not hold never wait`() = runTest {
        UiTestScenario.entries.forEach { scenario ->
            val launch = launchUiTest(scenario)
            UiTestHeldCall.entries.filterNot { it == scenario.heldCall }.forEach { call ->
                val result = startCall(call, launch.history, launch.directions)
                testScheduler.runCurrent()
                assertTrue(result.isCompleted, "$scenario: $call waited without being held")
            }
            stopKoin()
        }
    }

    @Test
    fun `FailedDelete throws on delete and keeps the activity and counts no delete`() = runTest {
        val launch = launchUiTest(UiTestScenario.FailedDelete)

        assertFailsWith<Exception> { launch.history.deleteActivity(UiTestFixtures.SEEDED_ACTIVITY_ID) }

        assertEquals(listOf(UiTestFixtures.seededActivity), launch.history.observeActivities().take(1).toList().single())
        assertEquals(UiTestFixtures.seededActivity, launch.history.getActivity(UiTestFixtures.SEEDED_ACTIVITY_ID))
        assertEquals(0, launch.controls.deleteCount)
    }

    @Test
    fun `DeleteTwice counts both held deletes of the same id and empties the history`() = runTest {
        val launch = launchUiTest(UiTestScenario.DeleteTwice)
        val first = async { launch.history.deleteActivity(UiTestFixtures.SEEDED_ACTIVITY_ID) }
        val second = async { launch.history.deleteActivity(UiTestFixtures.SEEDED_ACTIVITY_ID) }
        testScheduler.runCurrent()
        assertEquals(0, launch.controls.deleteCount)

        launch.controls.releaseHeldCalls()
        first.await()
        second.await()

        assertEquals(2, launch.controls.deleteCount)
        assertEquals(emptyList(), launch.history.observeActivities().take(1).toList().single())
    }

    @Test
    fun `GenerateTwice counts both held directions requests and completes both after release`() = runTest {
        val launch = launchUiTest(UiTestScenario.GenerateTwice)
        val first = async { launch.directions.getClosedRoute(UiTestFixtures.start, emptyList()) }
        val second = async { launch.directions.getClosedRoute(UiTestFixtures.start, emptyList()) }
        testScheduler.runCurrent()
        assertEquals(2, launch.controls.directionsRequestCount)
        assertEquals(0, launch.controls.directionsCompletedCount)

        launch.controls.releaseHeldCalls()

        assertEquals(UiTestFixtures.route, first.await().getOrThrow())
        assertEquals(UiTestFixtures.route, second.await().getOrThrow())
        assertEquals(2, launch.controls.directionsCompletedCount)
    }

    @Test
    fun `FinishTwice counts both held saves and keeps both activities with their own ids`() = runTest {
        val launch = launchUiTest(UiTestScenario.FinishTwice)
        val first = async { launch.history.saveActivity(newActivity) }
        val second = async { launch.history.saveActivity(newActivity) }
        testScheduler.runCurrent()
        assertEquals(0, launch.controls.saveCount)
        assertEquals(emptyList(), launch.history.observeActivities().take(1).toList().single())

        launch.controls.releaseHeldCalls()

        assertEquals(setOf(1L, 2L), setOf(first.await(), second.await()))
        assertEquals(2, launch.controls.saveCount)
        assertEquals(
            listOf(1L, 2L),
            launch.history.observeActivities().take(1).toList().single().map { it.id }
        )
    }

    @Test
    fun `FinishTwice walks the route point by point to its last point and stays open`() = runTest {
        val launch = launchUiTest(UiTestScenario.FinishTwice)
        val points = UiTestFixtures.route.points
        val updates = mutableListOf<LocationUpdate>()

        val collector = backgroundScope.launch { launch.location.observeLocationUpdates().toList(updates) }
        testScheduler.runCurrent()

        assertEquals(points.map { it.coordinates }, updates.map { assertIs<LocationUpdate.Success>(it).coordinates })
        assertEquals(points.last().coordinates, assertIs<LocationUpdate.Success>(updates.last()).coordinates)
        assertTrue(collector.isActive, "the location flow completed")
    }

    @Test
    fun `scenarios that do not walk emit no location update and stay open`() = runTest {
        UiTestScenario.entries.filterNot { it.walksRoute }.forEach { scenario ->
            val launch = launchUiTest(scenario)
            val updates = mutableListOf<LocationUpdate>()

            val collector = backgroundScope.launch { launch.location.observeLocationUpdates().toList(updates) }
            testScheduler.runCurrent()

            assertEquals(emptyList(), updates, "$scenario: updates")
            assertTrue(collector.isActive, "$scenario: the location flow completed")
            collector.cancel()
            stopKoin()
        }
    }

    @Test
    fun `the route is closed with at most ten points in ascending order`() {
        val points = UiTestFixtures.route.points

        assertTrue(points.size <= 10, "route has ${points.size} points")
        assertEquals(points.indices.toList(), points.map { it.order })
        assertEquals(UiTestFixtures.start, points.first().coordinates)
        assertEquals(UiTestFixtures.start, points.last().coordinates)
    }
}
