package dev.roozbahani.trailmetrics.domain.util

import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class SpeedCalculatorTest {
    private lateinit var speedCalculator: SpeedCalculator
    private val point1 = Coordinates(51.33816520152578, 12.385288438594552)
    private val point2 = Coordinates(51.338551183866215, 12.390722809535038)
    private val point3 = Coordinates(51.339014111023744, 12.395014789492011)

    @BeforeTest
    fun setup() {
        speedCalculator = SpeedCalculator(windowSize = 2)
    }

    @Test
    fun `calculate returns reported speed when accuracy is within acceptable range`() {
        val reportedSpeed = 10f
        val speed = speedCalculator.calculate(
            coordinates = point1,
            timestampMillis = 0L,
            reportedSpeedMetersPerSecond = reportedSpeed,
            accuracyMeters = 10f
        )

        assertEquals(reportedSpeed, speed)
    }

    @Test
    fun `calculate falls back to window calculation when accuracy is null`() {
        val timestampPoint1 = 0L
        val timestampPoint2 = 2000L

        speedCalculator.calculate(
            coordinates = point1,
            timestampMillis = timestampPoint1,
            reportedSpeedMetersPerSecond = 10f,
            accuracyMeters = 10f
        )
        val resultSpeed = speedCalculator.calculate(
            coordinates = point2,
            timestampMillis = timestampPoint2,
            reportedSpeedMetersPerSecond = 10f,
            accuracyMeters = null // Assuming the accuracy at point 2 is null
        )

        val deltaTimeSeconds = (timestampPoint2 - timestampPoint1) / 1000.00
        val distanceMeters = point1.distanceTo(point2)
        val expectedSpeed = (distanceMeters / deltaTimeSeconds).toFloat()

        assertEquals(expectedSpeed, resultSpeed)
    }

    @Test
    fun `calculate falls back to window calculation when accuracy exceeds threshold`() {
        val timestampPoint1 = 0L
        val timestampPoint2 = 2000L

        speedCalculator.calculate(
            coordinates = point1,
            timestampMillis = timestampPoint1,
            reportedSpeedMetersPerSecond = 10f,
            accuracyMeters = 10f
        )
        val resultSpeed = speedCalculator.calculate(
            coordinates = point2,
            timestampMillis = timestampPoint2,
            reportedSpeedMetersPerSecond = 10f,
            accuracyMeters = 50f // Assuming the accuracy at point exceeds the threshold (20f)
        )

        val deltaTimeSeconds = (timestampPoint2 - timestampPoint1) / 1000.00
        val distanceMeters = point1.distanceTo(point2)
        val expectedSpeed = (distanceMeters / deltaTimeSeconds).toFloat()

        assertEquals(expectedSpeed, resultSpeed)
    }

    @Test
    fun `calculate computes correct speed from window using distance and time`() {
        val timestampPoint1 = 0L
        val timestampPoint2 = 2000L

        speedCalculator.calculate(
            coordinates = point1,
            timestampMillis = timestampPoint1,
            reportedSpeedMetersPerSecond = null,
            accuracyMeters = null // Forcing window calculation
        )
        val resultSpeed = speedCalculator.calculate(
            coordinates = point2,
            timestampMillis = timestampPoint2,
            reportedSpeedMetersPerSecond = null,
            accuracyMeters = null // Forcing window calculation
        )

        val deltaTimeSeconds = (timestampPoint2 - timestampPoint1) / 1000.00
        val distanceMeters = point1.distanceTo(point2)
        val expectedSpeed = (distanceMeters / deltaTimeSeconds).toFloat()

        assertEquals(expectedSpeed, resultSpeed)
    }

    @Test
    fun `calculate returns null when window has zero elapsed time`() {
        speedCalculator.calculate(
            coordinates = point1,
            timestampMillis = 0L,
            reportedSpeedMetersPerSecond = null,
            accuracyMeters = null // Forcing window calculation
        )
        val resultSpeed = speedCalculator.calculate(
            coordinates = point2,
            timestampMillis = 0L,
            reportedSpeedMetersPerSecond = null,
            accuracyMeters = null // Forcing window calculation
        )

        assertNull(resultSpeed)
    }

    @Test
    fun `reset clears the internal sample window`() {
        speedCalculator.calculate(
            coordinates = point1,
            timestampMillis = 0L,
            reportedSpeedMetersPerSecond = null,
            accuracyMeters = null // Forcing window calculation
        )
        val speedBeforeReset = speedCalculator.calculate(
            coordinates = point2,
            timestampMillis = 2000L,
            reportedSpeedMetersPerSecond = null,
            accuracyMeters = null // Forcing window calculation
        )
        assertNotNull(speedBeforeReset)

        speedCalculator.reset() // Act Reset

        val speedAfterReset = speedCalculator.calculate(
            coordinates = point3,
            timestampMillis = 4000L,
            reportedSpeedMetersPerSecond = null,
            accuracyMeters = null // Forcing window calculation
        )

        assertNull(speedAfterReset)
    }

    @Test
    fun `window does not grow beyond windowSize`() {
        val timestampPoint1 = 0L
        val timestampPoint2 = 2000L
        val timestampPoint3 = 4000L

        speedCalculator.calculate(
            coordinates = point1,
            timestampMillis = timestampPoint1,
            reportedSpeedMetersPerSecond = null,
            accuracyMeters = null // Forcing window calculation
        )
        // Window now has 2 samples
        speedCalculator.calculate(
            coordinates = point2,
            timestampMillis = timestampPoint2,
            reportedSpeedMetersPerSecond = null,
            accuracyMeters = null // Forcing window calculation
        )

        // Adding sample 3 must remove sample 1 from window
        val resultSpeed = speedCalculator.calculate(
            coordinates = point3,
            timestampMillis = timestampPoint3,
            reportedSpeedMetersPerSecond = null,
            accuracyMeters = null // Forcing window calculation
        )

        // Now only point2 and point3 exist inside window,
        // then the calculation will be done based on these two points
        val deltaTimeSeconds = (timestampPoint3 - timestampPoint2) / 1000.00
        val distanceMeters = point2.distanceTo(point3)
        val expectedSpeed = (distanceMeters / deltaTimeSeconds).toFloat()

        assertEquals(expectedSpeed, resultSpeed)
    }
}
