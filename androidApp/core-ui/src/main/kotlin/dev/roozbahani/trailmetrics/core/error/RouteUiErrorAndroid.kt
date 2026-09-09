package dev.roozbahani.trailmetrics.core.error

import androidx.annotation.StringRes
import dev.roozbahani.trailmetrics.core.ui.R

@get:StringRes
val RouteUiError.stringRes: Int
    get() = when (this) {
        RouteUiError.LocationUnavailable -> R.string.msg_location_unavailable
        RouteUiError.MissingLocationPermission -> R.string.msg_missing_location_permission
        RouteUiError.General -> R.string.msg_general_location_error
    }
