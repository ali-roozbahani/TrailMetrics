package dev.roozbahani.trailmetrics.feature.tracking.fakes

import android.graphics.Bitmap
import android.os.Bundle
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.OnMapReadyCallback
import com.google.android.gms.maps.internal.ICameraUpdateFactoryDelegate
import com.google.android.gms.maps.internal.IGoogleMapDelegate
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowViewGroup
import java.lang.reflect.Method
import java.lang.reflect.Proxy

/**
 * A real [GoogleMap] over a fake delegate, for the Maps SDK that cannot run on the JVM.
 *
 * The Maps SDK talks to its implementation through `IInterface` delegates that Google Play
 * services normally provides. Here every delegate is a [Proxy] that does nothing and returns a
 * default (`0`, `false`, `null`, a [CameraPosition], or another such proxy for an interface), except
 * `snapshot`, whose callback is kept (and counted in [snapshotRequests]) until the test delivers it
 * with [deliverSnapshot]. That is the asynchronous part of `GoogleMap.snapshot { }` on a device.
 */
class FakeGoogleMap {

    /** Each pending request: the SDK's callback object and its Bitmap method (from the callback interface). */
    private val pendingSnapshots = mutableListOf<Pair<Any, Method>>()

    /** How many `snapshot` calls the map received, delivered or not. */
    var snapshotRequests: Int = 0
        private set

    /** How many `snapshot` calls are still waiting for [deliverSnapshot]. */
    val pendingSnapshotCount: Int
        get() = pendingSnapshots.size

    val map: GoogleMap = GoogleMap(
        fakeDelegate(IGoogleMapDelegate::class.java) { method, args ->
            if (method.name == "snapshot") {
                snapshotRequests++
                val callback = checkNotNull(args?.firstOrNull()) { "snapshot without a callback" }
                // The callback interface is obfuscated; its only Bitmap method delivers the snapshot.
                val onSnapshotReady = method.parameterTypes[0].methods.single {
                    it.parameterTypes.contentEquals(arrayOf(Bitmap::class.java))
                }
                pendingSnapshots += callback to onSnapshotReady
                Unit
            } else {
                null
            }
        }
    )

    /** Calls back the oldest pending snapshot request with [bitmap], as the SDK does once it has drawn the map. */
    fun deliverSnapshot(bitmap: Bitmap?) {
        check(pendingSnapshots.isNotEmpty()) { "no pending snapshot request" }
        val (callback, onSnapshotReady) = pendingSnapshots.removeAt(0)
        onSnapshotReady.invoke(callback, bitmap)
    }

    companion object {
        /** The map the next [ShadowMapView.getMapAsync] hands out; set by a test before it composes the screen. */
        var current: FakeGoogleMap? = null

        /**
         * Installs fake factories behind [CameraUpdateFactory] and [BitmapDescriptorFactory], which
         * `MapsInitializer` would otherwise fill from Google Play services. `TrackingScreen` builds a
         * camera update whenever the path changes, even when no map is shown.
         */
        fun installFactories() {
            CameraUpdateFactory.zza(fakeDelegate(ICameraUpdateFactoryDelegate::class.java) { _, _ -> null })
            // Its setter takes an obfuscated interface type: find it by its signature.
            val setter = BitmapDescriptorFactory::class.java.methods.single {
                it.name == "zza" && it.parameterTypes.size == 1 && it.parameterTypes[0].isInterface
            }
            setter.invoke(null, fakeDelegate(setter.parameterTypes[0]) { _, _ -> null })
        }
    }
}

/**
 * Stands in for [MapView] under Robolectric: no Google Play services lifecycle, and [getMapAsync]
 * answers at once with [FakeGoogleMap.current]'s map. Enabled per test class with
 * `@Config(shadows = [ShadowMapView::class])`.
 */
@Implements(MapView::class)
class ShadowMapView : ShadowViewGroup() { // A shadow extends the shadow of its class's superclass chain.

    @Implementation
    fun getMapAsync(callback: OnMapReadyCallback) {
        callback.onMapReady(checkNotNull(FakeGoogleMap.current) { "FakeGoogleMap.current is not set" }.map)
    }

    @Implementation
    fun onCreate(@Suppress("UNUSED_PARAMETER") savedInstanceState: Bundle?) = Unit

    @Implementation
    fun onStart() = Unit

    @Implementation
    fun onResume() = Unit

    @Implementation
    fun onPause() = Unit

    @Implementation
    fun onStop() = Unit

    @Implementation
    fun onDestroy() = Unit

    @Implementation
    fun onLowMemory() = Unit
}

/** [override] answers first; a `null` from it means "use the default". */
private fun <T : Any> fakeDelegate(type: Class<T>, override: (Method, Array<out Any?>?) -> Any?): T {
    val proxy = Proxy.newProxyInstance(type.classLoader, arrayOf(type)) { proxy, method, args ->
        when (method.name) {
            "equals" -> proxy === args?.firstOrNull()
            "hashCode" -> System.identityHashCode(proxy)
            "toString" -> "Fake${type.simpleName}"
            else -> override(method, args) ?: defaultValue(method.returnType)
        }
    }
    return checkNotNull(type.cast(proxy)) { "the proxy implements ${type.name}" }
}

private fun defaultValue(type: Class<*>): Any? = when {
    type == Void.TYPE -> null
    type == java.lang.Boolean.TYPE -> false
    type == Integer.TYPE -> 0
    type == java.lang.Long.TYPE -> 0L
    type == java.lang.Float.TYPE -> 0f
    type == java.lang.Double.TYPE -> 0.0
    type == CameraPosition::class.java -> CameraPosition.fromLatLngZoom(LatLng(0.0, 0.0), 0f)
    type.isInterface && type.name.startsWith("com.google.android.gms.") -> fakeDelegate(type) { _, _ -> null }
    else -> null
}
