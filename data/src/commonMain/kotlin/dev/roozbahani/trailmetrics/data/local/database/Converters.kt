package dev.roozbahani.trailmetrics.data.local.database

import androidx.room.TypeConverter
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlinx.serialization.json.Json

internal class Converters {
    @TypeConverter
    fun fromCoordinatesList(points: List<Coordinates>): String = Json.encodeToString(points)

    @TypeConverter
    fun toCoordinatesList(json: String): List<Coordinates> = Json.decodeFromString(json)

    @TypeConverter
    fun fromActivityType(activityType: ActivityType): String = activityType.name

    @TypeConverter
    fun toActivityType(value: String): ActivityType = ActivityType.valueOf(value)
}
