package dev.roozbahani.trailmetrics.data.tracking

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import dev.roozbahani.trailmetrics.data.R
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals

/** The tracking notification's texts come from the string resources of `data`, the same texts as before they moved there. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TrackingNotificationTextAndroidHostTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun metrics(distanceMeters: Double) = TrackingMetrics(
        elapsedMillis = 60_000L,
        lastUpdateElapsedRealtimeMillis = 60_000L,
        distanceMeters = distanceMeters,
        path = listOf(Coordinates(51.336, 12.388))
    )

    @Test
    fun `a tracking session shows the distance after Tracking`() {
        assertEquals("Tracking...1.23 km", trackingNotificationText(context, TrackingState.Tracking(metrics(1234.0))))
    }

    @Test
    fun `a paused session shows the distance after Paused`() {
        assertEquals("Paused - 850 m", trackingNotificationText(context, TrackingState.Paused(metrics(850.4))))
    }

    @Test
    fun `an idle or finished session shows Setting up`() {
        assertEquals("Setting up...", trackingNotificationText(context, TrackingState.Idle))
        assertEquals("Setting up...", trackingNotificationText(context, TrackingState.Finished(metrics(10.0))))
    }

    @Test
    fun `the title, the Stop label and the channel name keep their texts`() {
        assertEquals("TrailMetrics", context.getString(R.string.tracking_notification_title))
        assertEquals("Stop", context.getString(R.string.tracking_notification_stop))
        assertEquals("Tracking", context.getString(R.string.tracking_notification_channel))
    }
}
