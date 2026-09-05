package dev.roozbahani.trailmetrics.data.location

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.useContents
import kotlinx.coroutines.channels.ProducerScope
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import platform.CoreLocation.CLLocation
import platform.CoreLocation.CLLocationManager
import platform.CoreLocation.CLLocationManagerDelegateProtocol
import platform.CoreLocation.kCLLocationAccuracyBest
import platform.Foundation.NSError
import platform.darwin.NSObject
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume

private class LocationManagerDelegate(
    private val onUpdate: (CLLocation) -> Unit,
    private val onError: (NSError) -> Unit
) : NSObject(), CLLocationManagerDelegateProtocol {

    override fun locationManager(manager: CLLocationManager, didUpdateLocations: List<*>) {
        (didUpdateLocations.lastOrNull() as? CLLocation)?.let(onUpdate)
    }

    override fun locationManager(manager: CLLocationManager, didFailWithError: NSError) {
        onError(didFailWithError)
    }
}

@OptIn(ExperimentalForeignApi::class)
class IosLocationRepositoryImpl : LocationRepository {

    private var pendingCurrentLocation: Continuation<Result<Coordinates>>? = null
    private var updatesChannel: ProducerScope<LocationUpdate>? = null

    private val delegate = LocationManagerDelegate(
        onUpdate = { location ->
            val coordinates = location.coordinate.useContents {
                Coordinates(latitude = latitude, longitude = longitude)
            }

            pendingCurrentLocation?.let { continuation ->
                pendingCurrentLocation = null
                continuation.resume(Result.success(coordinates))
            }

            updatesChannel?.trySend(
                LocationUpdate.Success(
                    coordinates = coordinates,
                    speedMetersPerSecond = location.speed.takeIf { it >= 0 }?.toFloat(),
                    accuracyMeters = location.horizontalAccuracy.takeIf { it >= 0 }?.toFloat()
                )
            )
        },
        onError = { nsError ->
            val error = RouteError.LocationUnavailable(Throwable(nsError.localizedDescription))
            pendingCurrentLocation?.let { continuation ->
                pendingCurrentLocation = null
                continuation.resume(Result.failure(error))
            }
            updatesChannel?.trySend(LocationUpdate.Unavailable(error))
        }
    )

    private val locationManager = CLLocationManager().apply {
        desiredAccuracy = kCLLocationAccuracyBest
        delegate = this@IosLocationRepositoryImpl.delegate
    }

    override suspend fun getCurrentLocation(): Result<Coordinates> =
        suspendCancellableCoroutine { continuation ->
            pendingCurrentLocation = continuation
            continuation.invokeOnCancellation { pendingCurrentLocation = null }
            locationManager.requestLocation()
        }

    override fun observeLocationUpdates(): Flow<LocationUpdate> = callbackFlow {
        updatesChannel = this
        locationManager.startUpdatingLocation()
        awaitClose {
            locationManager.stopUpdatingLocation()
            updatesChannel = null
        }
    }
}
