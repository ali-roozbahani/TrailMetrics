package dev.roozbahani.trailmetrics.data.common

import dev.roozbahani.trailmetrics.domain.util.Logger
import platform.Foundation.NSLog

class IosLogger : Logger {
    override fun debug(tag: String, message: String) {
        NSLog("[$tag] $message")
    }
}

actual fun createLogger(): Logger = IosLogger()
