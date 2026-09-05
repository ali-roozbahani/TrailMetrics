package dev.roozbahani.trailmetrics.data.common

import platform.Foundation.NSUserDefaults

actual class KeyValueStorage {
    private val userDefaults = NSUserDefaults.standardUserDefaults
    actual fun getString(key: String): String? = userDefaults.stringForKey(key)

    actual fun putString(key: String, value: String) {
        userDefaults.setObject(value, key)
    }
}
