package dev.roozbahani.trailmetrics.core.error

import androidx.annotation.StringRes
import dev.roozbahani.trailmetrics.core.R
import dev.roozbahani.trailmetrics.domain.model.RouteError

data class RouteUiError(@param:StringRes val errorResId: Int)

class RouteUiErrorMapper {
    fun map(error: RouteError?): RouteUiError {
        return when (error) {
            is RouteError.LocationUnavailable -> {
                RouteUiError(R.string.msg_location_unavailable)
            }

            is RouteError.MissingLocationPermission -> {
                RouteUiError(R.string.msg_missing_location_permission)
            }

            else -> {
                RouteUiError(R.string.msg_general_location_error)
            }
        }
    }
}
