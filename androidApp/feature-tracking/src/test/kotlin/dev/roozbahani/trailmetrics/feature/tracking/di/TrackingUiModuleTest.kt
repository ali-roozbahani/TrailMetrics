package dev.roozbahani.trailmetrics.feature.tracking.di

import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import dev.roozbahani.trailmetrics.feature.tracking.TrackingAction
import dev.roozbahani.trailmetrics.feature.tracking.TrackingViewModel
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeClock
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeLogger
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeTrackingServiceLauncher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.koin.core.parameter.parametersOf
import org.koin.dsl.koinApplication
import org.koin.dsl.module
import kotlin.test.assertEquals

class TrackingUiModuleTest {

    private val testScheduler = TestCoroutineScheduler()
    private val clock = FakeClock(nowMillis = STARTED_AT)
    private val activityHistoryRepository = FakeActivityHistoryRepository()

    @OptIn(ExperimentalCoroutinesApi::class) // setMain/UnconfinedTestDispatcher have no stable replacement
    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
    }

    @OptIn(ExperimentalCoroutinesApi::class) // resetMain has no stable replacement
    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    /** The bindings the app's other modules provide, built from fakes. */
    private fun TestScope.collaboratorsModule() = module {
        single {
            TrackingSessionManager(
                locationRepository = FakeLocationRepository(),
                updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
                trackingServiceLauncher = FakeTrackingServiceLauncher(),
                speedCalculator = SpeedCalculator(),
                clock = clock,
                logger = FakeLogger(),
                scope = backgroundScope
            )
        }
        single<UserProfileRepository> { FakeUserProfileRepository(UserProfile(weightKg = 70.0)) }
        single<ActivityHistoryRepository> { activityHistoryRepository }
        single { CalorieCalculator() }
        single<Clock> { clock }
        single { SaveActivityUseCase(get(), get(), get()) }
    }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    @Test
    fun `trackingUiModule builds the ViewModel from the activity type and planned route parameters`() =
        runTest(testScheduler) {
            val koin = koinApplication { modules(trackingUiModule, collaboratorsModule()) }.koin

            val viewModel = koin.get<TrackingViewModel> { parametersOf(ActivityType.Running, PLANNED_ROUTE) }
            backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect {} }
            viewModel.onAction(TrackingAction.Start(PLANNED_ROUTE.first()))
            testScheduler.runCurrent()
            viewModel.onAction(TrackingAction.Stop)
            testScheduler.runCurrent()
            viewModel.onAction(TrackingAction.Finish(snapshotFilePath = null))
            testScheduler.runCurrent()

            assertEquals(PLANNED_ROUTE, viewModel.state.value.plannedRoutePoints)
            val record = activityHistoryRepository.savedActivities.single()
            assertEquals(ActivityType.Running, record.activityType)
            assertEquals(PLANNED_ROUTE, record.plannedRoutePoints)
            assertEquals(STARTED_AT, record.startedAtEpochMillis)
        }

    private companion object {
        const val STARTED_AT = 1_000_000L
        val PLANNED_ROUTE = listOf(
            Coordinates(latitude = 52.100, longitude = 13.100),
            Coordinates(latitude = 52.200, longitude = 13.200)
        )
    }
}
