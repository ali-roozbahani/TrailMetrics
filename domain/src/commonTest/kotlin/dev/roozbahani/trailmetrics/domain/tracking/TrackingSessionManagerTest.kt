package dev.roozbahani.trailmetrics.domain.tracking

import dev.roozbahani.trailmetrics.domain.fakes.FakeClock
import dev.roozbahani.trailmetrics.domain.fakes.FakeLocationRepository
import dev.roozbahani.trailmetrics.domain.fakes.FakeLogger
import dev.roozbahani.trailmetrics.domain.fakes.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class TrackingSessionManagerTest {

    private val locationRepository = FakeLocationRepository()
    private val clock = FakeClock()
    private val logger = FakeLogger()
    private val trackingService = FakeTrackingServiceLauncher()
    private val point1 = Coordinates(51.336, 12.388)
    private val point2 = Coordinates(51.327, 12.394)
    private val testScheduler = TestCoroutineScheduler()
    private val testScope = TestScope(StandardTestDispatcher(testScheduler))
    private lateinit var manager: TrackingSessionManager

    @BeforeTest
    fun setup() {
        manager = TrackingSessionManager(
            locationRepository = locationRepository,
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = trackingService,
            speedCalculator = SpeedCalculator(),
            clock = clock,
            logger = logger,
            scope = testScope
        )
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun `start transitions to Tracking and begins observing location`() = runTest(testScheduler) {
        // Arrange
        val updates = MutableSharedFlow<LocationUpdate>()
        locationRepository.setUpdatesFlow(updates)
        clock.setValues(0L, 100L)

        // Act
        manager.start(point1)
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(manager.currentState.value)

        updates.emit(LocationUpdate.Success(coordinates = point2, speedMetersPerSecond = null, accuracyMeters = null))
        testScheduler.advanceUntilIdle()

        val expectedPath = listOf(point1, point2)
        val actualPath = (manager.currentState.value as TrackingState.Tracking).metrics.path
        assertTrue(actualPath.size == expectedPath.size && actualPath.containsAll(expectedPath))
    }

    @Test
    fun `calling start twice does not create duplicate location observation`() = runTest(testScheduler) {
        // Arrange
        locationRepository.setUpdatesFlow(flowOf())
        clock.setValues(0L)

        // Act
        manager.start(point1)
        manager.start(point1)
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(manager.currentState.value)
        assertEquals(1, locationRepository.observeCallCount)

        val trackingState = manager.currentState.value as TrackingState.Tracking
        assertEquals(listOf(point1), trackingState.metrics.path)
    }

    @Test
    fun `pause stops location observation`() = runTest(testScheduler) {
        // Arrange
        val updates = MutableSharedFlow<LocationUpdate>()
        locationRepository.setUpdatesFlow(updates)
        clock.setValues(0L, 100L, 200L)

        // Act Start
        manager.start(point1)
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(manager.currentState.value)
        val trackingState = manager.currentState.value as TrackingState.Tracking
        assertEquals(listOf(point1), trackingState.metrics.path)

        // Act Pause
        manager.pause()
        testScheduler.runCurrent()

        assertIs<TrackingState.Paused>(manager.currentState.value)

        // Send new location update while paused
        updates.emit(LocationUpdate.Success(coordinates = point2, speedMetersPerSecond = null, accuracyMeters = null))
        testScheduler.advanceUntilIdle()

        // Still paused, path unchanged
        assertIs<TrackingState.Paused>(manager.currentState.value)
        val pausedState = manager.currentState.value as TrackingState.Paused
        assertEquals(listOf(point1), pausedState.metrics.path)
    }

    @Test
    fun `resume continues location observation after a pause`() = runTest(testScheduler) {
        // Arrange
        val updates = MutableSharedFlow<LocationUpdate>()
        locationRepository.setUpdatesFlow(updates)
        clock.setValues(0L, 100L, 200L)

        // Act Start
        manager.start(point1)
        testScheduler.runCurrent()

        assertIs<TrackingState.Tracking>(manager.currentState.value)
        assertEquals(listOf(point1), (manager.currentState.value as TrackingState.Tracking).metrics.path)

        // Act Pause
        manager.pause()
        testScheduler.runCurrent()

        assertIs<TrackingState.Paused>(manager.currentState.value)
        assertEquals(listOf(point1), (manager.currentState.value as TrackingState.Paused).metrics.path)

        // Act Resume
        manager.resume()
        testScheduler.runCurrent()

        updates.emit(LocationUpdate.Success(coordinates = point2, speedMetersPerSecond = null, accuracyMeters = null))
        testScheduler.advanceUntilIdle()

        assertIs<TrackingState.Tracking>(manager.currentState.value)
        val expectedPath = listOf(point1, point2)
        val actualPath = (manager.currentState.value as TrackingState.Tracking).metrics.path
        assertTrue(actualPath.size == expectedPath.size && actualPath.containsAll(expectedPath))
    }
}
