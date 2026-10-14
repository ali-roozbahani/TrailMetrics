package dev.roozbahani.trailmetrics.uitest

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.updateAndGet
import kotlin.coroutines.cancellation.CancellationException

/**
 * Reports [UiTestFixtures.start] as the current location. The update stream stays open like a
 * real GPS stream; when [walksRoute], it first emits one update per route point, in order, up to the second-to-last
 * one (the last point has the start's coordinates, which route progress cannot tell from index 0).
 */
internal class UiTestLocationRepository(private val walksRoute: Boolean) : LocationRepository {
    override suspend fun getCurrentLocation(): Result<Coordinates> = Result.success(UiTestFixtures.start)

    override fun observeLocationUpdates(): Flow<LocationUpdate> = flow {
        if (walksRoute) {
            UiTestFixtures.route.points.dropLast(1).forEach { point ->
                emit(
                    LocationUpdate.Success(
                        coordinates = point.coordinates,
                        speedMetersPerSecond = UiTestFixtures.WALK_SPEED_METERS_PER_SECOND,
                        accuracyMeters = UiTestFixtures.WALK_ACCURACY_METERS
                    )
                )
            }
        }
        awaitCancellation()
    }
}

/** Starts and stops nothing: no background location, no Live Activity. */
internal class UiTestTrackingServiceLauncher : TrackingServiceLauncher {
    override fun start() = Unit

    override fun stop() = Unit
}

/** Ignores the waypoints and returns [UiTestFixtures.route], counting requests and completions. */
internal class UiTestDirectionsRepository(private val controls: UiTestControls) : DirectionsRepository {
    override suspend fun getClosedRoute(startPoint: Coordinates, waypoints: List<Coordinates>): Result<Route> {
        controls.countDirectionsRequest()
        controls.awaitReleaseIfHeld(UiTestHeldCall.Directions)
        controls.countDirectionsCompleted()
        return Result.success(UiTestFixtures.route)
    }
}

/**
 * Keeps the history in a [MutableStateFlow], so [observeActivities] reflects saves and deletes
 * at once. A save assigns the next id from a counter and appends the record; a delete removes
 * the record and counts even if the id is already gone, unless the scenario fails deletes.
 */
internal class UiTestActivityHistoryRepository(
    private val scenario: UiTestScenario,
    private val controls: UiTestControls
) : ActivityHistoryRepository {
    private val activities = MutableStateFlow(
        if (scenario.seedsHistory) listOf(UiTestFixtures.seededActivity) else emptyList()
    )
    private val lastId = MutableStateFlow(activities.value.maxOfOrNull { it.id } ?: 0L)

    @Throws(Exception::class, CancellationException::class)
    override suspend fun saveActivity(activity: ActivityRecord): Long {
        controls.awaitReleaseIfHeld(UiTestHeldCall.Save)
        val id = lastId.updateAndGet { it + 1 }
        activities.update { it + activity.copy(id = id) }
        controls.countSave()
        return id
    }

    override fun observeActivities(): Flow<List<ActivityRecord>> = activities

    @Throws(Exception::class, CancellationException::class)
    override suspend fun getActivity(id: Long): ActivityRecord? = activities.value.firstOrNull { it.id == id }

    @Throws(Exception::class, CancellationException::class)
    override suspend fun deleteActivity(id: Long) {
        controls.awaitReleaseIfHeld(UiTestHeldCall.Delete)
        if (scenario.failsDelete) throw UiTestDeleteFailedException()
        activities.update { list -> list.filterNot { it.id == id } }
        controls.countDelete()
    }
}

/** Holds a saved profile from the start, so Start Tracking never asks for one. */
internal class UiTestUserProfileRepository : UserProfileRepository {
    private val profile = MutableStateFlow<UserProfile?>(UiTestFixtures.profile)

    @Throws(Exception::class, CancellationException::class)
    override suspend fun getUserProfile(): UserProfile? = profile.value

    @Throws(Exception::class, CancellationException::class)
    override suspend fun saveUserProfile(userProfile: UserProfile) {
        profile.value = userProfile
    }
}

/** The failure of every delete in [UiTestScenario.FailedDelete]. */
internal class UiTestDeleteFailedException : Exception("UI test scenario FailedDelete: delete failed")
