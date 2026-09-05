package dev.roozbahani.trailmetrics.data.common

import android.content.Context
import dev.roozbahani.trailmetrics.data.BuildKonfig
import io.ktor.client.engine.HttpClientEngineFactory
import io.ktor.client.engine.okhttp.OkHttp
import org.koin.mp.KoinPlatform.getKoin

actual val httpClientEngine: HttpClientEngineFactory<*> = OkHttp

actual fun platformDefaultHeaders(): Map<String, String> {
    val context: Context = getKoin().get<Context>()
    return mapOf(
        "X-Android-Package" to context.packageName,
        "X-Android-Cert" to BuildKonfig.ANDROID_CERT_SHA1.replace(":", "")
    )
}
