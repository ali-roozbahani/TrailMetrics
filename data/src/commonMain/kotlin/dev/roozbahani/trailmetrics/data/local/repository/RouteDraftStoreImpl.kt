package dev.roozbahani.trailmetrics.data.local.repository

import dev.roozbahani.trailmetrics.data.local.dao.RouteDraftDao
import dev.roozbahani.trailmetrics.data.local.entity.RouteDraftEntity
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.Route
import dev.roozbahani.trailmetrics.domain.model.RoutePoint
import dev.roozbahani.trailmetrics.domain.route.RouteDraftStore
import dev.roozbahani.trailmetrics.domain.route.StoredRouteDraft
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.withContext

// Every storage access switches to [ioDispatcher] itself, so a caller never depends on Room's query context.
class RouteDraftStoreImpl(
    private val routeDraftDao: RouteDraftDao,
    private val ioDispatcher: CoroutineDispatcher
) : RouteDraftStore {

    override suspend fun save(draft: StoredRouteDraft) = withContext(ioDispatcher) {
        if (draft.isEmpty) {
            routeDraftDao.clear()
            return@withContext
        }
        routeDraftDao.upsert(
            RouteDraftEntity(
                startLatitude = draft.startPoint?.latitude,
                startLongitude = draft.startPoint?.longitude,
                waypoints = draft.waypoints.map { it.coordinates },
                generatedRoutePoints = draft.generatedRoute?.points?.map { it.coordinates },
                generatedRouteDistanceMeters = draft.generatedRoute?.distanceMeters,
                activityType = draft.activityType
            )
        )
    }

    override suspend fun load(): StoredRouteDraft? = withContext(ioDispatcher) {
        val row = routeDraftDao.get() ?: return@withContext null
        val startPoint = if (row.startLatitude != null && row.startLongitude != null) {
            Coordinates(row.startLatitude, row.startLongitude)
        } else {
            null
        }
        val routePoints = row.generatedRoutePoints
        val generatedRoute = if (routePoints != null) {
            val distanceMeters = checkNotNull(row.generatedRouteDistanceMeters) { "Stored route without a distance" }
            Route(points = routePoints.toRoutePoints(), distanceMeters = distanceMeters)
        } else {
            null
        }
        StoredRouteDraft(
            startPoint = startPoint,
            waypoints = row.waypoints.toRoutePoints(),
            generatedRoute = generatedRoute,
            activityType = row.activityType
        )
    }

    override suspend fun clear() = withContext(ioDispatcher) {
        routeDraftDao.clear()
    }
}

private fun List<Coordinates>.toRoutePoints(): List<RoutePoint> =
    mapIndexed { index, coordinates -> RoutePoint(coordinates = coordinates, order = index) }
