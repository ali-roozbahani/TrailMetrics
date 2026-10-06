package dev.roozbahani.trailmetrics.feature.tracking

import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import dev.roozbahani.trailmetrics.feature.tracking.di.trackingUiModule
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeClock
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeLogger
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeTrackingServiceLauncher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.koin.core.context.startKoin
import org.koin.core.context.stopKoin
import org.koin.dsl.module

/**
 * The collaborators of the real [TrackingViewModel] that [trackingUiModule] builds, as fakes: a real
 * [TrackingSessionManager] over [locationRepository], a real [SaveActivityUseCase] over
 * [activityHistoryRepository]. Shared by the Compose UI test classes of the tracking screen.
 */
class TrackingScreenFixture {

    private val testScheduler = TestCoroutineScheduler()

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private val sessionScope = CoroutineScope(SupervisorJob() + UnconfinedTestDispatcher(testScheduler))

    val locationRepository = FakeLocationRepository()
    val trackingServiceLauncher = FakeTrackingServiceLauncher()
    val clock = FakeClock(nowMillis = STARTED_AT, elapsedRealtimeMillis = START_ELAPSED_REALTIME)
    val userProfileRepository = FakeUserProfileRepository(PROFILE)
    val activityHistoryRepository = FakeActivityHistoryRepository()
    val sessionManager = TrackingSessionManager(
        locationRepository = locationRepository,
        updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
        trackingServiceLauncher = trackingServiceLauncher,
        speedCalculator = SpeedCalculator(),
        clock = clock,
        logger = FakeLogger(),
        scope = sessionScope
    )

    @OptIn(ExperimentalCoroutinesApi::class) // setMain/UnconfinedTestDispatcher have no stable replacement
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        startKoin {
            modules(
                trackingUiModule,
                module {
                    single { sessionManager }
                    single<UserProfileRepository> { userProfileRepository }
                    single { CalorieCalculator() }
                    single<Clock> { clock }
                    single { SaveActivityUseCase(activityHistoryRepository, CalorieCalculator(), clock) }
                }
            )
        }
    }

    @OptIn(ExperimentalCoroutinesApi::class) // resetMain has no stable replacement
    fun tearDown() {
        stopKoin()
        sessionScope.cancel()
        Dispatchers.resetMain()
    }

    /** A location fix [millisAfterStart] after Start, as the location service would deliver it. */
    fun receiveLocation(coordinates: Coordinates, millisAfterStart: Long) {
        clock.elapsedRealtimeMillis = START_ELAPSED_REALTIME + millisAfterStart
        locationRepository.emit(LocationUpdate.Success(coordinates, speedMetersPerSecond = null, accuracyMeters = null))
    }

    /** Enough consecutive failures for the session manager to report [reason]. */
    fun receiveUnavailable(reason: RouteError) {
        repeat(UNAVAILABLE_THRESHOLD) { locationRepository.emit(LocationUpdate.Unavailable(reason)) }
    }

    companion object {
        const val STARTED_AT = 1_000_000L
        const val START_ELAPSED_REALTIME = 5_000L

        /** TrackingSessionManager reports a location issue after this many consecutive failures. */
        const val UNAVAILABLE_THRESHOLD = 3

        val PROFILE = UserProfile(weightKg = 70.0)
        val START = Coordinates(latitude = 52.000, longitude = 13.000)
        val NEXT = Coordinates(latitude = 52.001, longitude = 13.000)

        /** A short planned route from [START] to [END] (~222 m): reaching [END] completes it. */
        val END = Coordinates(latitude = 52.002, longitude = 13.000)
        val WALKED_ROUTE = listOf(START, NEXT, END)
    }
}
