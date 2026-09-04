package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.fakes.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.fakes.FakeClock
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class SaveActivityUseCaseTest {

    private val activityHistoryRepository = FakeActivityHistoryRepository()
    private val calorieCalculator = CalorieCalculator() // real instance: pure, deterministic, already covered by CalorieCalculatorTest
    private val clock = FakeClock()
    private lateinit var useCase: SaveActivityUseCase

    private val point1 = Coordinates(51.336, 12.388)
    private val point2 = Coordinates(51.337, 12.389)

    @BeforeTest
    fun setup() {
        useCase = SaveActivityUseCase(
            activityHistoryRepository = activityHistoryRepository,
            calorieCalculator = calorieCalculator,
            clock = clock
        )
    }

    @Test
    fun `invoke calculates calories and saves activity when average speed is available`() = runTest {
        // Arrange
        val metrics = TrackingMetrics(
            elapsedMillis = 600_000L,
            lastUpdateTimestampMillis = 1_600L,
            distanceMeters = 2200.0,
            path = listOf(point1, point2),
            currentSpeedMetersPerSecond = 3f
        )
        val plannedRoutePoints = listOf(point1, point2)
        val weightKg = 80.0
        val startedAt = 1_000L
        val endedAt = 1_600L

        clock.setValues(endedAt)
        activityHistoryRepository.nextSavedId = 42L

        // Real CalorieCalculator is deterministic — compute the expected value
        // by calling it directly instead of hardcoding a number that could
        // silently drift from the real formula.
        val expectedCalories = calorieCalculator.calculate(
            activityType = ActivityType.Running,
            averageSpeedMetersPerSecond = metrics.averageSpeedMetersPerSecond ?: 0f,
            weightKg = weightKg,
            durationMillis = metrics.elapsedMillis
        )

        // Act
        val resultId = useCase(
            activityType = ActivityType.Running,
            plannedRoutePoints = plannedRoutePoints,
            metrics = metrics,
            weightKg = weightKg,
            startedAtEpochMillis = startedAt,
            snapshotFilePath = "path/to/snapshot.png"
        )

        // Assert
        assertEquals(42L, resultId)

        val savedRecord = activityHistoryRepository.savedActivities.single()
        assertEquals(ActivityType.Running, savedRecord.activityType)
        assertEquals(startedAt, savedRecord.startedAtEpochMillis)
        assertEquals(endedAt, savedRecord.endedAtEpochMillis)
        assertEquals(metrics.distanceMeters, savedRecord.distanceMeters)
        assertEquals(metrics.elapsedMillis, savedRecord.durationMillis)
        assertEquals(metrics.averageSpeedMetersPerSecond, savedRecord.averageSpeedMetersPerSecond)
        assertEquals(expectedCalories, savedRecord.calories)
        assertEquals(plannedRoutePoints, savedRecord.plannedRoutePoints)
        assertEquals(metrics.path, savedRecord.actualPath)
        assertEquals("path/to/snapshot.png", savedRecord.snapshotFilePath)
    }

    @Test
    fun `invoke saves null calories when average speed is unavailable`() = runTest {
        // Arrange: zero elapsed time makes averageSpeedMetersPerSecond null
        val metrics = TrackingMetrics(
            elapsedMillis = 0L,
            lastUpdateTimestampMillis = 1_000L,
            distanceMeters = 0.0,
            path = listOf(point1)
        )

        clock.setValues(1_000L)
        activityHistoryRepository.nextSavedId = 1L

        // Act
        useCase(
            activityType = ActivityType.Walking,
            plannedRoutePoints = emptyList(),
            metrics = metrics,
            weightKg = 70.0,
            startedAtEpochMillis = 1_000L,
            snapshotFilePath = null
        )

        // Assert
        val savedRecord = activityHistoryRepository.savedActivities.single()
        assertNull(savedRecord.calories)
    }
}
