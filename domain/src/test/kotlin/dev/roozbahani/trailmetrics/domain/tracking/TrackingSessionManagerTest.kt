package dev.roozbahani.trailmetrics.domain.tracking

import com.google.common.truth.Truth.assertThat
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.Logger
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Test

class TrackingSessionManagerTest {

    private val locationRepository = mockk<LocationRepository>()
    private val clock = mockk<Clock>()
    private val logger = mockk<Logger>(relaxed = true)
    private val trackingService = mockk<TrackingServiceLauncher>(relaxed = true)
    private val point1 = Coordinates(51.336, 12.388)
    private val point2 = Coordinates(51.327, 12.394)

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun `start transitions to Tracking and begins observing location`() = runTest {
        // Arrange
        val updates = MutableSharedFlow<LocationUpdate>()
        every { locationRepository.observeLocationUpdates() } returns updates
        every { clock.nowMillis() } returnsMany listOf(0L, 100L)

        val testScope = TestScope(StandardTestDispatcher(testScheduler))
        val manager = TrackingSessionManager(
            locationRepository = locationRepository,
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = trackingService,
            clock = clock,
            logger = logger,
            scope = testScope
        )

        // Act
        manager.start(point1)
        assertThat(manager.currentState.value).isInstanceOf(TrackingState.Tracking::class.java)

        testScheduler.runCurrent()

        updates.emit(LocationUpdate.Success(point2))
        testScheduler.advanceUntilIdle()

        assertThat((manager.currentState.value as TrackingState.Tracking).metrics.path)
            .containsExactly(
                point1,
                point2
            )
    }

    @Test
    fun `calling start twice does not create duplicate location observation`() = runTest {
        // Arrange
        every { locationRepository.observeLocationUpdates() } returns flowOf()
        every { clock.nowMillis() } returns 0L

        val testScope = TestScope(StandardTestDispatcher(testScheduler))
        val manager = TrackingSessionManager(
            locationRepository = locationRepository,
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = trackingService,
            clock = clock,
            logger = logger,
            scope = testScope
        )

        // Act
        manager.start(point1)
        manager.start(point1)
        testScheduler.runCurrent()

        assertThat(manager.currentState.value).isInstanceOf(TrackingState.Tracking::class.java)
        verify(exactly = 1) { locationRepository.observeLocationUpdates() }

        val trackingState = manager.currentState.value as TrackingState.Tracking
        assertThat(trackingState.metrics.path).containsExactly(point1)
    }

    @Test
    fun `pause stops location observation`() = runTest {
        // Arrange
        val updates = MutableSharedFlow<LocationUpdate>()
        every { locationRepository.observeLocationUpdates() } returns updates
        every { clock.nowMillis() } returnsMany listOf(0L, 100L, 200L)

        val testScope = TestScope(StandardTestDispatcher(testScheduler))
        val manager = TrackingSessionManager(
            locationRepository = locationRepository,
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = trackingService,
            clock = clock,
            logger = logger,
            scope = testScope
        )

        // Act Start
        manager.start(point1)
        testScheduler.runCurrent()

        // Assert it's tracking
        assertThat(manager.currentState.value).isInstanceOf(TrackingState.Tracking::class.java)
        val trackingState = manager.currentState.value as TrackingState.Tracking
        assertThat(trackingState.metrics.path).containsExactly(point1)

        // Act Pause
        manager.pause()
        testScheduler.runCurrent()

        // Assert it's paused
        assertThat(manager.currentState.value).isInstanceOf(TrackingState.Paused::class.java)

        // Send new location update
        updates.emit(LocationUpdate.Success(point2))
        testScheduler.advanceUntilIdle()

        // Assert it's still paused
        assertThat(manager.currentState.value).isInstanceOf(TrackingState.Paused::class.java)
        val pausedState = manager.currentState.value as TrackingState.Paused
        assertThat(pausedState.metrics.path).containsExactly(point1)
    }

    @Test
    fun `resume continues location observation after a pause`() = runTest {
        // Arrange
        val updates = MutableSharedFlow<LocationUpdate>()
        every { locationRepository.observeLocationUpdates() } returns updates
        every { clock.nowMillis() } returnsMany listOf(0L, 100L, 200L)

        val testScope = TestScope(StandardTestDispatcher(testScheduler))
        val manager = TrackingSessionManager(
            locationRepository = locationRepository,
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = trackingService,
            clock = clock,
            logger = logger,
            scope = testScope
        )

        // Act Start
        manager.start(point1)
        testScheduler.runCurrent()

        // Assert it's tracking
        assertThat(manager.currentState.value).isInstanceOf(TrackingState.Tracking::class.java)
        assertThat((manager.currentState.value as TrackingState.Tracking).metrics.path)
            .containsExactly(point1)

        // Act Pause
        manager.pause()
        testScheduler.runCurrent()

        // Assert it's paused
        assertThat(manager.currentState.value).isInstanceOf(TrackingState.Paused::class.java)
        assertThat((manager.currentState.value as TrackingState.Paused).metrics.path)
            .containsExactly(point1)

        // Act Resume
        manager.resume()
        testScheduler.runCurrent()
        updates.emit(LocationUpdate.Success(point2))
        testScheduler.advanceUntilIdle()

        // Assert it's resumed
        assertThat(manager.currentState.value).isInstanceOf(TrackingState.Tracking::class.java)
        assertThat((manager.currentState.value as TrackingState.Tracking).metrics.path)
            .containsExactly(point1, point2)
    }
}
