package dev.roozbahani.trailmetrics.shared.uitest

import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.repository.DirectionsRepository
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import org.koin.core.module.Module
import org.koin.dsl.module

/**
 * The bindings that replace the production ones in UI-test mode. With these five overridden,
 * nothing resolves the Room database, the iOS location repository, the HTTP client or the
 * user-defaults storage, so Koin (whose singles are lazy) never creates them.
 */
internal fun uiTestOverrideModule(scenario: UiTestScenario, controls: UiTestControls): Module = module {
    single<LocationRepository> { UiTestLocationRepository(walksRoute = scenario.walksRoute) }
    single<TrackingServiceLauncher> { UiTestTrackingServiceLauncher() }
    single<DirectionsRepository> { UiTestDirectionsRepository(controls) }
    single<ActivityHistoryRepository> { UiTestActivityHistoryRepository(scenario, controls) }
    single<UserProfileRepository> { UiTestUserProfileRepository() }
}
