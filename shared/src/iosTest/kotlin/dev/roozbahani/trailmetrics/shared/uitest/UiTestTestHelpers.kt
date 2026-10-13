package dev.roozbahani.trailmetrics.shared.uitest

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.TestScope
import org.koin.mp.KoinPlatform

/** The history a scenario starts with. */
internal fun initialHistory(scenario: UiTestScenario): List<ActivityRecord> =
    if (scenario.seedsHistory) listOf(UiTestFixtures.seededActivity) else emptyList()

/** The four counters, in the order directions requests, directions completed, saves, deletes. */
internal fun UiTestControls.counters(): List<Int> =
    listOf(directionsRequestCount, directionsCompletedCount, saveCount, deleteCount)

/** An activity as the app saves it: id 0, the repository assigns the real one. */
internal val newActivity: ActivityRecord = UiTestFixtures.seededActivity.copy(id = 0)

/**
 * Starts [call] in the test's background scope, so a held call left waiting never blocks the end
 * of the test, and keeps its outcome (a failure too) in the returned value.
 */
internal fun TestScope.startCall(
    call: UiTestHeldCall,
    history: ActivityHistoryRepository,
    directions: DirectionsRepository
): Deferred<Result<Any?>> = backgroundScope.async {
    runCatching {
        when (call) {
            UiTestHeldCall.Delete -> history.deleteActivity(UiTestFixtures.SEEDED_ACTIVITY_ID)
            UiTestHeldCall.Directions -> directions.getClosedRoute(UiTestFixtures.start, emptyList()).getOrThrow()
            UiTestHeldCall.Save -> history.saveActivity(newActivity)
        }
    }
}

/** The fakes one launch through [doInitKoinIosForUiTest] resolves to, with its controls. */
internal class UiTestLaunch(
    val controls: UiTestControls,
    val history: ActivityHistoryRepository,
    val directions: DirectionsRepository,
    val location: LocationRepository
)

/** Launches [scenario] through the entry and resolves the fakes from Koin. Stop Koin afterwards. */
internal fun launchUiTest(scenario: UiTestScenario): UiTestLaunch {
    val controls = doInitKoinIosForUiTest(scenario)
    val koin = KoinPlatform.getKoin()
    return UiTestLaunch(controls, koin.get(), koin.get(), koin.get())
}
