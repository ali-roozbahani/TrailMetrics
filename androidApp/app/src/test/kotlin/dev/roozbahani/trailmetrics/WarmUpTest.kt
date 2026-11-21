@file:OptIn(ExperimentalCoroutinesApi::class) // the test dispatchers have no stable replacement

package dev.roozbahani.trailmetrics

import dev.roozbahani.trailmetrics.core.testing.FakeLogger
import dev.roozbahani.trailmetrics.core.testing.FakeClock
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingSessionStore
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.data.di.ioDispatcherQualifier
import dev.roozbahani.trailmetrics.di.APPLICATION_SCOPE
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.Logger
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import kotlinx.coroutines.CoroutineDispatcher
import org.koin.dsl.koinApplication
import org.koin.dsl.module
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

class WarmUpFirstScreensTest {

    private class Directions : DirectionsRepository {
        override suspend fun getClosedRoute(startPoint: Coordinates, waypoints: List<Coordinates>): Result<Route> =
            Result.failure(UnsupportedOperationException("not used"))
    }

    @Test
    fun `the manager, the directions repository and the profile repository are built on the injected dispatcher`() = runTest {
        val built = mutableListOf<String>()
        val queue = StandardTestDispatcher(testScheduler)
        val koin = koinApplication {
            modules(
                module {
                    single<CoroutineScope>(APPLICATION_SCOPE) { CoroutineScope(UnconfinedTestDispatcher(testScheduler)) }
                    single<CoroutineDispatcher>(ioDispatcherQualifier) { queue }
                    single<Logger> { FakeLogger() }
                    single<TrackingSessionManager> {
                        built += "manager"
                        TrackingSessionManager(
                            locationRepository = FakeLocationRepository(),
                            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
                            trackingServiceLauncher = FakeTrackingServiceLauncher(),
                            speedCalculator = SpeedCalculator(),
                            clock = FakeClock(),
                            logger = FakeLogger(),
                            trackingSessionStore = FakeTrackingSessionStore(),
                            scope = CoroutineScope(UnconfinedTestDispatcher(testScheduler))
                        )
                    }
                    single<DirectionsRepository> { built += "directions"; Directions() }
                    single<UserProfileRepository> { built += "profile"; FakeUserProfileRepository() }
                }
            )
        }.koin

        val job = warmUpFirstScreens(koin)

        assertEquals(emptyList(), built, "something was built on the caller's thread")
        testScheduler.runCurrent()
        job.join()
        assertEquals(listOf("manager", "directions", "profile"), built)
    }
}
