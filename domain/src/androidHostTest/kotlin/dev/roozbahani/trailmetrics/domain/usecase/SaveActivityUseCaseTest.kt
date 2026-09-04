package dev.roozbahani.trailmetrics.domain.usecase

import com.google.common.truth.Truth.assertThat
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.Clock
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Before
import org.junit.Test

class SaveActivityUseCaseTest {

    private val activityHistoryRepository = mockk<ActivityHistoryRepository>()
    private val calorieCalculator = mockk<CalorieCalculator>()
    private val clock = mockk<Clock>()
    private lateinit var useCase: SaveActivityUseCase

    private val point1 = Coordinates(51.336, 12.388)
    private val point2 = Coordinates(51.337, 12.389)

    @Before
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
        val expectedCalories = 120.0

        every { clock.nowMillis() } returns endedAt
        every {
            calorieCalculator.calculate(
                activityType = ActivityType.Running,
                averageSpeedMetersPerSecond = metrics.averageSpeedMetersPerSecond ?: 0f,
                weightKg = weightKg,
                durationMillis = metrics.elapsedMillis
            )
        } returns expectedCalories
        coEvery { activityHistoryRepository.saveActivity(any()) } returns 42L

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
        assertThat(resultId).isEqualTo(42L)

        coVerify {
            activityHistoryRepository.saveActivity(
                withArg { record: ActivityRecord ->
                    assertThat(record.activityType).isEqualTo(ActivityType.Running)
                    assertThat(record.startedAtEpochMillis).isEqualTo(startedAt)
                    assertThat(record.endedAtEpochMillis).isEqualTo(endedAt)
                    assertThat(record.distanceMeters).isEqualTo(metrics.distanceMeters)
                    assertThat(record.durationMillis).isEqualTo(metrics.elapsedMillis)
                    assertThat(record.averageSpeedMetersPerSecond)
                        .isEqualTo(metrics.averageSpeedMetersPerSecond)
                    assertThat(record.calories).isEqualTo(expectedCalories)
                    assertThat(record.plannedRoutePoints).isEqualTo(plannedRoutePoints)
                    assertThat(record.actualPath).isEqualTo(metrics.path)
                    assertThat(record.snapshotFilePath).isEqualTo("path/to/snapshot.png")
                }
            )
        }
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

        every { clock.nowMillis() } returns 1_000L
        coEvery { activityHistoryRepository.saveActivity(any()) } returns 1L

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
        coVerify {
            activityHistoryRepository.saveActivity(
                withArg { record: ActivityRecord ->
                    assertThat(record.calories).isNull()
                }
            )
        }
    }
}
