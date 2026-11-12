package dev.roozbahani.trailmetrics.uitest

import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.route.RouteDraftStore
import dev.roozbahani.trailmetrics.domain.tracking.StoredTrackingSession
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionStore
import org.koin.core.module.Module
import org.koin.dsl.module

/**
 * The bindings that replace the production ones in UI-test mode. With these seven overridden,
 * nothing resolves the Room database, the iOS location repository, the HTTP client or the
 * user-defaults storage, so Koin (whose singles are lazy) never creates them.
 */
internal fun uiTestOverrideModule(scenario: UiTestScenario, controls: UiTestControls): Module = module {
    single<LocationRepository> { UiTestLocationRepository(walksRoute = scenario.walksRoute) }
    single<TrackingServiceLauncher> { UiTestTrackingServiceLauncher() }
    single<TrackingSessionStore> { UiTestTrackingSessionStore(controls, scenario.storedSession()) }
    single<RouteDraftStore> { UiTestRouteDraftStore() }
    single<DirectionsRepository> { UiTestDirectionsRepository(controls) }
    single<ActivityHistoryRepository> { UiTestActivityHistoryRepository(scenario, controls) }
    single<UserProfileRepository> { UiTestUserProfileRepository() }
}

private fun UiTestScenario.storedSession(): StoredTrackingSession? =
    if (storesPausedSession) UiTestFixtures.pausedSession else null
