package dev.roozbahani.trailmetrics.navigation

import android.os.Bundle
import androidx.navigation.NavType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

val CoordinatesNavType = object : NavType<Coordinates>(isNullableAllowed = false) {
    override fun get(bundle: Bundle, key: String): Coordinates? {
        return bundle.getString(key)?.let { Json.decodeFromString<Coordinates>(it) }
    }

    override fun parseValue(value: String): Coordinates {
        return Json.decodeFromString(value)
    }

    override fun serializeAsValue(value: Coordinates): String {
        return Json.encodeToString(value)
    }

    override fun put(bundle: Bundle, key: String, value: Coordinates) {
        bundle.putString(key, Json.encodeToString(value))
    }
}

val PlannedRoutePointsNavType = object : NavType<List<Coordinates>>(isNullableAllowed = false) {
    override fun get(bundle: Bundle, key: String): List<Coordinates>? {
        return bundle.getString(key)?.let { Json.decodeFromString<List<Coordinates>>(it) }
    }

    override fun parseValue(value: String): List<Coordinates> {
        return Json.decodeFromString(value)
    }

    override fun serializeAsValue(value: List<Coordinates>): String {
        return Json.encodeToString(value)
    }

    override fun put(bundle: Bundle, key: String, value: List<Coordinates>) {
        bundle.putString(key, Json.encodeToString(value))
    }
}
