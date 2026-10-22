package dev.roozbahani.trailmetrics.shared.di

import android.content.SharedPreferences
import org.koin.dsl.module
import kotlin.test.Test

class KoinGraphAndroidTest {

    // The Play Services location client needs a Context and a device, and its type is not on this
    // module's compile classpath (data keeps it as an implementation dependency), so it is named by
    // string. LocationRepository, its only consumer, is overridden.
    @Test
    fun `every definition of the Android graph resolves`() {
        checkKoinGraph(
            overrides = listOf(commonFakesModule, androidFakesModule),
            notResolved = setOf("com.google.android.gms.location.FusedLocationProviderClient")
        )
    }

    // KeyValueStorage stays real; only the SharedPreferences it wraps, which comes from a Context, is faked.
    private val androidFakesModule = module {
        single<SharedPreferences> { FakeSharedPreferences() }
    }
}
