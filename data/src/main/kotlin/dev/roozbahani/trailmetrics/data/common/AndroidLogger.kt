package dev.roozbahani.trailmetrics.data.common

import android.util.Log
import dev.roozbahani.trailmetrics.domain.util.Logger

class AndroidLogger: Logger {
    override fun debug(tag: String, message: String) {
        Log.d(tag, message)
    }
}