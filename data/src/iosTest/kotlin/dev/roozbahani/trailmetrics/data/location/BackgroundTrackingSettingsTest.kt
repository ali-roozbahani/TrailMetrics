package dev.roozbahani.trailmetrics.data.location

import platform.CoreLocation.CLActivityType
import platform.CoreLocation.CLActivityTypeFitness
import platform.CoreLocation.CLActivityTypeOther
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private class FakeLocationManagerSettings : LocationManagerSettings {
    override var allowsBackgroundLocationUpdates = false
    override var pausesLocationUpdatesAutomatically = true
    override var activityType: CLActivityType = CLActivityTypeOther
}

class BackgroundTrackingSettingsTest {

    @Test
    fun `a running session keeps updating in the background and is not paused by the system`() {
        val settings = FakeLocationManagerSettings()

        applyBackgroundTracking(settings, enabled = true)

        assertTrue(settings.allowsBackgroundLocationUpdates)
        assertFalse(settings.pausesLocationUpdatesAutomatically)
    }

    @Test
    fun `a running session sets the fitness activity type`() {
        val settings = FakeLocationManagerSettings()

        applyBackgroundTracking(settings, enabled = true)

        assertEquals(CLActivityTypeFitness, settings.activityType)
    }

    @Test
    fun `the end of a session puts the manager back as it was`() {
        val settings = FakeLocationManagerSettings()
        applyBackgroundTracking(settings, enabled = true)

        applyBackgroundTracking(settings, enabled = false)

        assertFalse(settings.allowsBackgroundLocationUpdates)
        assertTrue(settings.pausesLocationUpdatesAutomatically)
        assertEquals(CLActivityTypeOther, settings.activityType)
    }
}
