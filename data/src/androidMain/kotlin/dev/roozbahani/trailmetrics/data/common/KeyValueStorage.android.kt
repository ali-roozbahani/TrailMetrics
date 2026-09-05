package dev.roozbahani.trailmetrics.data.common

import android.content.SharedPreferences
import androidx.core.content.edit

actual class KeyValueStorage(private val sharedPreferences: SharedPreferences) {
    actual fun getString(key: String): String? =
        sharedPreferences.getString(key, null)

    actual fun putString(key: String, value: String) {
        sharedPreferences.edit { putString(key, value) }
    }
}
