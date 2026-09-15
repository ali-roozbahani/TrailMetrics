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
import platform.CoreLocation.CLAuthorizationStatus
import platform.CoreLocation.CLLocation
import platform.CoreLocation.CLLocationManager
import platform.CoreLocation.CLLocationManagerDelegateProtocol
import platform.CoreLocation.kCLAuthorizationStatusAuthorizedAlways
import platform.CoreLocation.kCLAuthorizationStatusAuthorizedWhenInUse
import platform.CoreLocation.kCLAuthorizationStatusNotDetermined
import platform.CoreLocation.kCLLocationAccuracyBest
import platform.Foundation.NSError
import platform.darwin.NSObject
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume

private class LocationManagerDelegate(
    private val onUpdate: (CLLocation) -> Unit,
    private val onError: (NSError) -> Unit,
    private val onAuthorizationChange: (CLAuthorizationStatus) -> Unit
) : NSObject(), CLLocationManagerDelegateProtocol {

    override fun locationManager(manager: CLLocationManager, didUpdateLocations: List<*>) {
        (didUpdateLocations.lastOrNull() as? CLLocation)?.let(onUpdate)
    }

    override fun locationManager(manager: CLLocationManager, didFailWithError: NSError) {
        onError(didFailWithError)
    }

    override fun locationManagerDidChangeAuthorization(manager: CLLocationManager) {
        onAuthorizationChange(manager.authorizationStatus)
    }
}

@OptIn(ExperimentalForeignApi::class)
class IosLocationRepositoryImpl : LocationRepository {

    private var pendingCurrentLocation: Continuation<Result<Coordinates>>? = null
    private var pendingAuthorization: Continuation<Boolean>? = null
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
        },
        onAuthorizationChange = { status ->
            if (status != kCLAuthorizationStatusNotDetermined) {
                pendingAuthorization?.let { continuation ->
                    pendingAuthorization = null
                    val granted = status == kCLAuthorizationStatusAuthorizedWhenInUse ||
                        status == kCLAuthorizationStatusAuthorizedAlways
                    continuation.resume(granted)
                }
            }
        }
    )

    private val locationManager = CLLocationManager().apply {
        desiredAccuracy = kCLLocationAccuracyBest
        delegate = this@IosLocationRepositoryImpl.delegate
    }

    override suspend fun getCurrentLocation(): Result<Coordinates> {
        if (!ensureLocationPermission()) {
            return Result.failure(RouteError.MissingLocationPermission())
        }

        return suspendCancellableCoroutine { continuation ->
            pendingCurrentLocation = continuation
            continuation.invokeOnCancellation { pendingCurrentLocation = null }
            locationManager.requestLocation()
        }
    }

    private suspend fun ensureLocationPermission(): Boolean {
        return when (locationManager.authorizationStatus) {
            kCLAuthorizationStatusAuthorizedWhenInUse, kCLAuthorizationStatusAuthorizedAlways -> true
            kCLAuthorizationStatusNotDetermined -> requestAuthorization()
            else -> false
        }
    }

    private suspend fun requestAuthorization(): Boolean = suspendCancellableCoroutine { continuation ->
        pendingAuthorization = continuation
        continuation.invokeOnCancellation { pendingAuthorization = null }
        locationManager.requestWhenInUseAuthorization()
    }

    override fun observeLocationUpdates(): Flow<LocationUpdate> = callbackFlow {
        if (ensureLocationPermission()) {
            updatesChannel = this
            locationManager.startUpdatingLocation()
        } else {
            trySend(LocationUpdate.Unavailable(RouteError.MissingLocationPermission()))
        }

        awaitClose {
            locationManager.stopUpdatingLocation()
            updatesChannel = null
        }
    }

    fun setBackgroundUpdatesEnabled(enabled: Boolean) {
        if (enabled) {
            // Escalates WhenInUse -> Always, specifically for Tracking (never called from
            // Route's getCurrentLocation() path). A no-op if already Always, already
            // denied/restricted, or WhenInUse hasn't been granted yet.
            locationManager.requestAlwaysAuthorization()
        }
        locationManager.allowsBackgroundLocationUpdates = enabled
        locationManager.pausesLocationUpdatesAutomatically = !enabled
    }
}
