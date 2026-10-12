package dev.roozbahani.trailmetrics.data.local.database

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlin.test.Test
import kotlin.test.assertEquals

class ConvertersTest {

    private val converters = Converters()

    // Stored rows hold the enum constant's name and are read back with ActivityType.valueOf.
    // Renaming a constant would make every existing row of that type fail to load, so these
    // literals must change only together with a database migration.
    private val storedNames = mapOf(
        ActivityType.Running to "Running",
        ActivityType.Cycling to "Cycling",
        ActivityType.Walking to "Walking",
    )

    @Test
    fun `every activity type has a pinned stored name`() {
        assertEquals(ActivityType.entries.toSet(), storedNames.keys)
    }

    @Test
    fun `fromActivityType writes the pinned stored name`() {
        storedNames.forEach { (type, stored) ->
            assertEquals(stored, converters.fromActivityType(type))
        }
    }

    @Test
    fun `toActivityType reads the pinned stored name`() {
        storedNames.forEach { (type, stored) ->
            assertEquals(type, converters.toActivityType(stored))
        }
    }

    // Stored rows hold coordinate lists as this JSON text. A different form (renamed keys, another
    // encoding) would make every existing route and path fail to load, so these literals must
    // change only together with a database migration.
    private val storedCoordinateLists = mapOf(
        listOf(Coordinates(51.336, 12.388), Coordinates(-33.8688, 151.2093)) to
            """[{"latitude":51.336,"longitude":12.388},{"latitude":-33.8688,"longitude":151.2093}]""",
        emptyList<Coordinates>() to "[]",
    )

    @Test
    fun `fromCoordinatesList writes the pinned stored form`() {
        storedCoordinateLists.forEach { (points, stored) ->
            assertEquals(stored, converters.fromCoordinatesList(points))
        }
    }

    @Test
    fun `toCoordinatesList reads the pinned stored form`() {
        storedCoordinateLists.forEach { (points, stored) ->
            assertEquals(points, converters.toCoordinatesList(stored))
        }
    }
}
