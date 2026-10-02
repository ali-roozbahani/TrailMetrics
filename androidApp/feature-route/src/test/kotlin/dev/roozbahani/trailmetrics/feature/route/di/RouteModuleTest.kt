package dev.roozbahani.trailmetrics.feature.route.di

import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.usecase.GenerateClosedRouteUseCase
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import dev.roozbahani.trailmetrics.feature.route.RouteAction
import dev.roozbahani.trailmetrics.feature.route.RouteState
import dev.roozbahani.trailmetrics.feature.route.RouteViewModel
import dev.roozbahani.trailmetrics.feature.route.fakes.FakeDirectionsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.koin.dsl.koinApplication
import org.koin.dsl.module
import kotlin.test.assertEquals

class RouteModuleTest {

    private val testScheduler = TestCoroutineScheduler()
    private val locationRepository = FakeLocationRepository(Result.success(START))
    private val directionsRepository = FakeDirectionsRepository(Result.success(ROUTE))
    private val userProfileRepository = FakeUserProfileRepository(PROFILE)

    /** The bindings the app's other modules provide, built from fakes. */
    private val collaboratorsModule = module {
        single { GetCurrentLocationUseCase(locationRepository) }
        single { GenerateClosedRouteUseCase(directionsRepository) }
        single<UserProfileRepository> { userProfileRepository }
    }

    private val koin = koinApplication { modules(routeModule, collaboratorsModule) }.koin

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

    @Test
    fun `routeModule builds RouteViewModel on the provided location use case and profile repository`() =
        runTest(testScheduler) {
            val viewModel = koin.get<RouteViewModel>()
            testScheduler.runCurrent()

            assertEquals(RouteState(startPoint = START, userProfile = PROFILE), viewModel.state.value)
            assertEquals(1, locationRepository.getCurrentLocationCalls)
            assertEquals(1, userProfileRepository.getUserProfileCalls)
        }

    @Test
    fun `routeModule builds RouteViewModel on the provided route generation use case`() = runTest(testScheduler) {
        val viewModel = koin.get<RouteViewModel>()
        testScheduler.runCurrent()
        listOf(WP_A, WP_B, WP_C).forEach { viewModel.onAction(RouteAction.MapTapped(it)) }

        viewModel.onAction(RouteAction.GenerateRouteClicked)
        testScheduler.runCurrent()

        assertEquals(listOf(START to listOf(WP_A, WP_B, WP_C)), directionsRepository.requests)
        assertEquals(ROUTE, viewModel.state.value.generatedRoute)
    }

    private companion object {
        val START = Coordinates(latitude = 52.52, longitude = 13.405)
        val WP_A = Coordinates(latitude = 52.521, longitude = 13.406)
        val WP_B = Coordinates(latitude = 52.522, longitude = 13.407)
        val WP_C = Coordinates(latitude = 52.523, longitude = 13.408)
        val PROFILE = UserProfile(weightKg = 70.0)
        val ROUTE = Route(
            points = listOf(RoutePoint(START, 0), RoutePoint(WP_A, 1), RoutePoint(START, 2)),
            distanceMeters = 500.0
        )
    }
}
