package dev.roozbahani.trailmetrics.data.common

expect class KeyValueStorage {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
}
