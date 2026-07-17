package dev.roozbahani.trailmetrics.data.location

import android.Manifest
import android.location.Location
import android.os.Looper
import androidx.annotation.RequiresPermission
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class LocationRepositoryImpl(
    private val locationProvider: FusedLocationProviderClient
) : LocationRepository {


    @RequiresPermission(
        anyOf = [
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ]
    )
    override suspend fun getCurrentLocation(): Result<Coordinates> {
        return try {
            val location = suspendCancellableCoroutine<Location?> { continuation ->
                val cancellationTokenSource = CancellationTokenSource()

                continuation.invokeOnCancellation {
                    cancellationTokenSource.cancel()
                }

                locationProvider.getCurrentLocation(
                    Priority.PRIORITY_HIGH_ACCURACY,
                    cancellationTokenSource.token
                ).addOnSuccessListener { location ->
                    continuation.resume(location)
                }.addOnFailureListener { ex ->
                    continuation.resumeWithException(ex)
                }
            }

            if (location != null) {
                Result.success(Coordinates(location.latitude, location.longitude))
            } else {
                Result.failure(RouteError.LocationUnavailable())
            }

        } catch (_: SecurityException) {
            Result.failure(RouteError.MissingLocationPermission())
        } catch (ex: Exception) {
            Result.failure(RouteError.LocationUnavailable(ex))
        }
    }

    @RequiresPermission(
        anyOf = [
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ]
    )
    override fun observeLocationUpdates(): Flow<LocationUpdate> = callbackFlow {
        val locationRequest = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY,
            LOCATION_UPDATE_INTERVAL_MILLIS
        ).build()

        val locationCallback: LocationCallback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                result.lastLocation?.let {
                    trySend(
                        LocationUpdate.Success(
                            Coordinates(
                                latitude = it.latitude,
                                longitude = it.longitude
                            )
                        )
                    )
                } ?: run {
                    trySend(LocationUpdate.Unavailable(RouteError.LocationUnavailable()))
                }
            }

            override fun onLocationAvailability(availability: LocationAvailability) {
                if (!availability.isLocationAvailable)
                    trySend(LocationUpdate.Unavailable(RouteError.LocationUnavailable()))
            }
        }

        try {
            locationProvider.requestLocationUpdates(
                locationRequest,
                locationCallback,
                Looper.getMainLooper()
            )
        } catch (_: SecurityException) {
            trySend(LocationUpdate.Unavailable(RouteError.MissingLocationPermission()))
        } catch (ex: CancellationException) {
            throw ex // propagate to parent scope
        } catch (ex: Exception) {
            trySend(LocationUpdate.Unavailable(RouteError.LocationUnavailable(ex)))
        } finally {
            awaitClose {
                locationProvider.removeLocationUpdates(locationCallback)
            }
        }
    }

    companion object {
        const val LOCATION_UPDATE_INTERVAL_MILLIS = 3_000L
    }
}
