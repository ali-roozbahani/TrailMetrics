package dev.roozbahani.trailmetrics.data.local.database

import androidx.room3.ColumnTypeConverter
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlinx.serialization.json.Json

internal class Converters {
    @ColumnTypeConverter
    fun fromCoordinatesList(points: List<Coordinates>): String = Json.encodeToString(points)

    @ColumnTypeConverter
    fun toCoordinatesList(json: String): List<Coordinates> = Json.decodeFromString(json)

    @ColumnTypeConverter
    fun fromActivityType(activityType: ActivityType): String = activityType.name

    @ColumnTypeConverter
    fun toActivityType(value: String): ActivityType = ActivityType.valueOf(value)
}
