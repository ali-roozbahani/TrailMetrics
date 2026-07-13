package dev.roozbahani.trailmetrics.data.location

import android.Manifest
import android.location.Location
import androidx.annotation.RequiresPermission
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.RouteError
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import kotlinx.coroutines.flow.Flow
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

    override fun observeLocationUpdates(): Flow<Coordinates> {
        TODO("Not yet implemented")
    }
}
