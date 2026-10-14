package dev.roozbahani.trailmetrics.uitest

import dev.roozbahani.trailmetrics.domain.model.RouteDraft
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import dev.roozbahani.trailmetrics.shared.di.KoinHelper
import dev.roozbahani.trailmetrics.shared.di.initKoin
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.koin.core.annotation.KoinInternalApi
import org.koin.core.context.stopKoin
import org.koin.mp.KoinPlatform
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotSame
import kotlin.test.assertTrue

class UiTestEntryTest {

    @AfterTest
    fun tearDown() {
        stopKoin()
    }

    @Test
    fun `KoinHelper and the Koin bindings return the fakes in every scenario`() = runTest {
        UiTestScenario.entries.forEach { scenario ->
            val controls = doInitKoinIosForUiTest(scenario)
            controls.releaseHeldCalls()
            val helper = KoinHelper()

            assertIs<UiTestActivityHistoryRepository>(helper.getActivityHistoryRepository(), "$scenario: history")
            assertIs<UiTestUserProfileRepository>(helper.userProfileRepository(), "$scenario: profile")
            assertEquals(UiTestFixtures.profile, helper.userProfileRepository().getUserProfile(), "$scenario")
            assertEquals(UiTestFixtures.start, helper.getCurrentLocationUseCase().invoke(), "$scenario: location")
            assertEquals(UiTestFixtures.route, helper.generateClosedRouteUseCase().invoke(threeWaypointDraft()), "$scenario")
            assertEquals(1, controls.directionsRequestCount, "$scenario: directions requests")
            assertEquals(1, controls.directionsCompletedCount, "$scenario: directions completed")

            val koin = KoinPlatform.getKoin()
            assertIs<UiTestLocationRepository>(koin.get<LocationRepository>(), "$scenario: location binding")
            assertIs<UiTestTrackingServiceLauncher>(koin.get<TrackingServiceLauncher>(), "$scenario: launcher")
            assertIs<UiTestDirectionsRepository>(koin.get<DirectionsRepository>(), "$scenario: directions binding")
            stopKoin()
        }
    }

    @OptIn(KoinInternalApi::class)
    @Test
    fun `no database or location repository or HTTP client or user defaults is created in any scenario`() {
        UiTestScenario.entries.forEach { scenario ->
            doInitKoinIosForUiTest(scenario)
            resolveEverythingTheAppReaches()

            // The only Koin internal API used: the registry of definitions and their factories.
            val factories = KoinPlatform.getKoin().instanceRegistry.instances.values
            val byType = factories.groupBy { it.beanDefinition.primaryType.qualifiedName }
            NEVER_CREATED_TYPES.forEach { typeName ->
                val definitions = byType[typeName].orEmpty()
                assertTrue(definitions.isNotEmpty(), "$scenario: no definition of $typeName is registered")
                assertTrue(definitions.none { it.isCreated() }, "$scenario: $typeName was created")
            }
            // The same check sees an instance that was created: the fake history repository.
            val historyFactories = byType[ACTIVITY_HISTORY_REPOSITORY].orEmpty()
            assertTrue(historyFactories.all { it.isCreated() }, "$scenario: the check does not see created singles")
            stopKoin()
        }
    }

    @Test
    fun `fakes passed through initKoin's declaration are replaced by the production modules`() = runTest {
        val scenario = UiTestScenario.FailedDelete
        initKoin { modules(uiTestOverrideModule(scenario, UiTestControls(scenario))) }

        val profileRepository = KoinPlatform.getKoin().get<UserProfileRepository>()

        assertFalse(
            profileRepository is UiTestUserProfileRepository,
            "initKoin { modules(...) } kept the fake; the trap the entry avoids is gone"
        )
    }

    @Test
    fun `a second launch after stopKoin has fresh controls and counters and gate and history`() = runTest {
        UiTestScenario.entries.forEach { scenario ->
            val first = doInitKoinIosForUiTest(scenario)
            first.releaseHeldCalls()
            val firstHistory = KoinHelper().getActivityHistoryRepository()
            firstHistory.saveActivity(newActivity)
            KoinHelper().generateClosedRouteUseCase().invoke(threeWaypointDraft())
            stopKoin()

            val second = doInitKoinIosForUiTest(scenario)
            val history = KoinHelper().getActivityHistoryRepository()

            assertNotSame(first, second, "$scenario: controls")
            assertNotSame(firstHistory, history, "$scenario: history fake")
            assertEquals(listOf(0, 0, 0, 0), second.counters(), "$scenario: counters")
            assertEquals(initialHistory(scenario), history.observeActivities().first(), "$scenario: history")
            scenario.heldCall?.let { heldCall ->
                val call = startCall(heldCall, history, KoinPlatform.getKoin().get())
                testScheduler.runCurrent()
                assertFalse(call.isCompleted, "$scenario: the second launch's gate is already open")
                second.releaseHeldCalls()
                testScheduler.runCurrent()
            }
            stopKoin()
        }
    }

    private fun threeWaypointDraft() = RouteDraft(
        startPoint = RoutePoint(UiTestFixtures.start, order = 0),
        waypoints = UiTestFixtures.route.points.take(3)
    )

    private fun resolveEverythingTheAppReaches() {
        val helper = KoinHelper()
        helper.getActivityHistoryRepository()
        helper.getCurrentLocationUseCase()
        helper.generateClosedRouteUseCase()
        helper.userProfileRepository()
        helper.trackingSessionManager()
        helper.saveActivityUseCase()
        helper.observeActivitiesUseCase()
        helper.calorieCalculator()
        helper.clock()
        val koin = KoinPlatform.getKoin()
        koin.get<LocationRepository>()
        koin.get<TrackingServiceLauncher>()
        koin.get<DirectionsRepository>()
    }

    private companion object {
        const val ACTIVITY_HISTORY_REPOSITORY = "dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository"

        // By name: shared-uitest's test classpath doesn't have Room or Ktor, so their class literals
        // can't be used here. Each name must match a registered definition, so a rename fails.
        val NEVER_CREATED_TYPES = listOf(
            "dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase",
            "dev.roozbahani.trailmetrics.data.location.IosLocationRepositoryImpl",
            "io.ktor.client.HttpClient",
            "dev.roozbahani.trailmetrics.data.common.KeyValueStorage"
        )
    }
}
