package dev.roozbahani.trailmetrics.domain.tracking

/**
 * Switches location updates that keep arriving while the app is in the background on or off.
 *
 * Separate from `LocationRepository` on purpose: Android keeps location updates alive with a foreground
 * service (`TrackingServiceLauncher`), so it has nothing to switch. Only a platform whose location source
 * needs the switch implements it.
 */
interface BackgroundLocationUpdates {
    fun setEnabled(enabled: Boolean)
}
