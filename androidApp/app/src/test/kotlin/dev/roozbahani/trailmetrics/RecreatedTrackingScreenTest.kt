package dev.roozbahani.trailmetrics

import android.app.Application
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalInspectionMode
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import dev.roozbahani.trailmetrics.core.designsystem.theme.TrailMetricsTheme
import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.core.testing.FakeClock
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLogger
import dev.roozbahani.trailmetrics.core.testing.FakeSnapshotFileDeleter
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingServiceLauncher
import dev.roozbahani.trailmetrics.core.testing.FakeTrackingSessionStore
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.Clock
import dev.roozbahani.trailmetrics.domain.util.SnapshotFileDeleter
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import dev.roozbahani.trailmetrics.feature.tracking.TrackingScreen
import dev.roozbahani.trailmetrics.feature.tracking.di.trackingUiModule
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.koin.core.context.startKoin
import org.koin.core.context.stopKoin
import org.koin.dsl.module
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import dev.roozbahani.trailmetrics.feature.tracking.R as TrackingR

/**
 * What the user sees after the Activity was recreated while a session was stored: the saved session is offered
 * by the real [SavedSessionOfferViewModel], and the real Tracking screen opens on that offer. The planned
 * route is what ends the walk: reaching its end shows the completed card, which an empty plan never does.
 * The map is not rendered (no Maps SDK on the JVM), so the plan is seen through that behavior.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class) // not TrailMetricsApplication: it would start the real Koin
class RecreatedTrackingScreenTest {

    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val scheduler = TestCoroutineScheduler()

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private val sessionScope = CoroutineScope(SupervisorJob() + UnconfinedTestDispatcher(scheduler))
    private val locationRepository = FakeLocationRepository()
    private val clock = FakeClock(nowMillis = STARTED_AT, elapsedRealtimeMillis = START_ELAPSED_REALTIME)
    private val store = FakeTrackingSessionStore()

    @OptIn(ExperimentalCoroutinesApi::class) // setMain/UnconfinedTestDispatcher have no stable replacement
    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher(scheduler))
    }

    @OptIn(ExperimentalCoroutinesApi::class) // resetMain has no stable replacement
    @After
    fun tearDown() {
        stopKoin()
        sessionScope.cancel()
        Dispatchers.resetMain()
    }

    // The manager of the recreated process: it knows the session only from the store.
    private fun newManager() = TrackingSessionManager(
        locationRepository = locationRepository,
        updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
        trackingServiceLauncher = FakeTrackingServiceLauncher(),
        speedCalculator = SpeedCalculator(),
        clock = clock,
        logger = FakeLogger(),
        trackingSessionStore = store,
        scope = sessionScope
    )

    private fun storePausedSessionOn(plan: List<Coordinates>) {
        store.stored = TrackingState.Paused(
            TrackingMetrics(
                elapsedMillis = 30_000L,
                lastUpdateElapsedRealtimeMillis = START_ELAPSED_REALTIME,
                distanceMeters = 111.0,
                path = listOf(START, NEXT)
            )
        )
        store.storedActivityType = ActivityType.Running
        store.storedStartedAtEpochMillis = STARTED_AT
        store.storedPlannedRoute = plan
    }

    /** Opens the Tracking screen on the offer that the recreated Activity gets, as the nav host does. */
    private fun openOfferedTrackingScreen() {
        val manager = newManager()
        startKoin {
            modules(
                trackingUiModule,
                module {
                    single { manager }
                    single<UserProfileRepository> { FakeUserProfileRepository(UserProfile(weightKg = 70.0)) }
                    single { CalorieCalculator() }
                    single<Clock> { clock }
                    single { SaveActivityUseCase(FakeActivityHistoryRepository(), CalorieCalculator(), clock) }
                    single<SnapshotFileDeleter> { FakeSnapshotFileDeleter(deleteFromDisk = true) }
                }
            )
        }
        val offer = checkNotNull(SavedSessionOfferViewModel(manager, FakeLogger()).state.value.offer) {
            "the stored session was not offered"
        }
        rule.setContent {
            TrailMetricsTheme {
                CompositionLocalProvider(LocalInspectionMode provides true) {
                    TrackingScreen(
                        initialStartPoint = offer.startPoint,
                        plannedRoutePoints = offer.plannedRoutePoints,
                        activityType = offer.selectedActivityType,
                        onNavigateBack = {}
                    )
                }
            }
        }
        rule.waitForIdle()
    }

    private fun resumeAndWalkTo(coordinates: Coordinates) {
        rule.onNode(hasText(rule.activity.getString(TrackingR.string.btn_tracking_resume)) and hasClickAction())
            .performClick()
        clock.elapsedRealtimeMillis = START_ELAPSED_REALTIME + 60_000L
        locationRepository.emit(LocationUpdate.Success(coordinates, speedMetersPerSecond = null, accuracyMeters = null))
        rule.waitForIdle()
    }

    @Test
    fun `a recreated Tracking screen shows the planned route again, so walking to its end completes it`() {
        storePausedSessionOn(PLAN)
        openOfferedTrackingScreen()

        resumeAndWalkTo(END)

        rule.onNodeWithText(rule.activity.getString(TrackingR.string.msg_route_completed)).assertExists()
    }

    @Test
    fun `a recreated Tracking screen of a session with no plan does not complete at any point`() {
        storePausedSessionOn(emptyList())
        openOfferedTrackingScreen()

        resumeAndWalkTo(END)

        rule.onNodeWithText(rule.activity.getString(TrackingR.string.msg_route_completed)).assertDoesNotExist()
        assertEquals(emptyList(), store.storedPlannedRoute)
    }

    private companion object {
        const val STARTED_AT = 1_000_000L
        const val START_ELAPSED_REALTIME = 5_000L
        val START = Coordinates(latitude = 52.000, longitude = 13.000)
        val NEXT = Coordinates(latitude = 52.001, longitude = 13.000)

        /** ~222 m from [START]: reaching it completes the plan. */
        val END = Coordinates(latitude = 52.002, longitude = 13.000)
        val PLAN = listOf(START, NEXT, END)
    }
}
