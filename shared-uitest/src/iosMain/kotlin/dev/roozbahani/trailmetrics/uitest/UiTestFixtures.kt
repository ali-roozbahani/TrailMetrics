package dev.roozbahani.trailmetrics.uitest

import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.model.UserProfile

/**
 * Fixed values every scenario's fakes return. No clock, no randomness: timestamps are constants
 * and activity ids come from a counter.
 */
internal object UiTestFixtures {
    /** The current location every scenario reports. */
    val start = Coordinates(latitude = 52.52, longitude = 13.405)

    /** The saved user profile, so Start Tracking never asks for one. */
    val profile = UserProfile(weightKg = 70.0)

    /**
     * A small closed loop around [start], shaped like what `DirectionsRepositoryImpl` returns:
     * the decoded overview polyline from the start back to the start (coordinates at 1e-5
     * precision, `order` counting up from 0) and the summed leg distance.
     */
    val route = Route(
        points = listOf(
            Coordinates(52.52, 13.405),
            Coordinates(52.5209, 13.405),
            Coordinates(52.5218, 13.405),
            Coordinates(52.5218, 13.40648),
            Coordinates(52.5218, 13.40796),
            Coordinates(52.5209, 13.40796),
            Coordinates(52.52, 13.40796),
            Coordinates(52.52, 13.40648),
            Coordinates(52.52, 13.405)
        ).mapIndexed { index, coordinates -> RoutePoint(coordinates = coordinates, order = index) },
        distanceMeters = 800.0
    )

    /** Id of the activity seeded in the scenarios that start with history. */
    const val SEEDED_ACTIVITY_ID = 1L

    private const val SEEDED_STARTED_AT_EPOCH_MILLIS = 1_760_000_000_000L
    private const val SEEDED_DURATION_MILLIS = 600_000L

    /** The one activity in a seeded history. */
    val seededActivity = ActivityRecord(
        id = SEEDED_ACTIVITY_ID,
        activityType = ActivityType.Running,
        startedAtEpochMillis = SEEDED_STARTED_AT_EPOCH_MILLIS,
        endedAtEpochMillis = SEEDED_STARTED_AT_EPOCH_MILLIS + SEEDED_DURATION_MILLIS,
        distanceMeters = route.distanceMeters,
        durationMillis = SEEDED_DURATION_MILLIS,
        averageSpeedMetersPerSecond = 1.33f,
        calories = 55.0,
        plannedRoutePoints = route.points.map { it.coordinates },
        actualPath = route.points.map { it.coordinates },
        snapshotFilePath = null
    )

    /** Speed and accuracy of each walked location update (accurate enough to be used). */
    const val WALK_SPEED_METERS_PER_SECOND = 1.5f
    const val WALK_ACCURACY_METERS = 5f
}
