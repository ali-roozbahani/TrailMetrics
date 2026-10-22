package dev.roozbahani.trailmetrics.shared.di

import dev.roozbahani.trailmetrics.data.location.IosLocationRepositoryImpl
import kotlin.test.Test

class KoinGraphIosTest {

    // IosLocationRepositoryImpl is a final class around CLLocationManager, so it cannot be faked: its two
    // consumers (LocationRepository, TrackingServiceLauncher) are overridden and it is not resolved.
    @Test
    fun `every definition of the iOS graph resolves`() {
        checkKoinGraph(
            overrides = listOf(commonFakesModule),
            notResolved = setOf(IosLocationRepositoryImpl::class.qualifiedName!!)
        )
    }
}
