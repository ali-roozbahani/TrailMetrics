package dev.roozbahani.trailmetrics.domain.util

import dev.roozbahani.trailmetrics.domain.model.ActivityType
import kotlin.math.nextDown
import kotlin.math.nextUp
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

class CalorieCalculatorTest {

    private lateinit var calorieCalculator: CalorieCalculator

    @BeforeTest
    fun setup() {
        calorieCalculator = CalorieCalculator()
    }

    @Test
    fun `calculate returns correct calories for walking at moderate pace`() {
        val weightKg = 85.0
        val durationMins = 30
        val speedKmh = 4f

        val resultCalories = calorieCalculator.calculate(
            activityType = ActivityType.Walking,
            averageSpeedMetersPerSecond = speedKmh.toMetersPerSecond(),
            weightKg = weightKg,
            durationMillis = durationMins.toMillis()
        )

        val expectedMet = 2.8
        val expectedCalories = expectedMet * weightKg * durationMins.toHours()

        assertEquals(expected = expectedCalories, actual = resultCalories, absoluteTolerance = 0.01)
    }

    @Test
    fun `calculate returns correct calories for running at moderate pace`() {
        val weightKg = 85.0
        val durationMins = 30
        val speedKmh = 8.5f

        val resultCalories = calorieCalculator.calculate(
            activityType = ActivityType.Running,
            averageSpeedMetersPerSecond = speedKmh.toMetersPerSecond(),
            weightKg = weightKg,
            durationMillis = durationMins.toMillis()
        )

        val expectedMet = 9.0
        val expectedCalories = expectedMet * weightKg * durationMins.toHours()

        assertEquals(expected = expectedCalories, actual = resultCalories, absoluteTolerance = 0.01)
    }

    @Test
    fun `calculate returns correct calories for cycling at moderate pace`() {
        val weightKg = 85.0
        val durationMins = 30
        val speedKmh = 20.0f

        val resultCalories = calorieCalculator.calculate(
            activityType = ActivityType.Cycling,
            averageSpeedMetersPerSecond = speedKmh.toMetersPerSecond(),
            weightKg = weightKg,
            durationMillis = durationMins.toMillis()
        )

        val expectedMet = 8.0
        val expectedCalories = expectedMet * weightKg * durationMins.toHours()

        assertEquals(expected = expectedCalories, actual = resultCalories, absoluteTolerance = 0.01)
    }

    @Test
    fun `calculate uses correct MET at walking speed boundary`() {
        val weightKg = 85.0
        val durationMins = 30
        val speedKmh = 3.19f

        val resultCalories = calorieCalculator.calculate(
            activityType = ActivityType.Walking,
            averageSpeedMetersPerSecond = speedKmh.toMetersPerSecond(),
            weightKg = weightKg,
            durationMillis = durationMins.toMillis()
        )

        val expectedMet = 2.0
        val expectedCalories = expectedMet * weightKg * durationMins.toHours()

        assertEquals(expected = expectedCalories, actual = resultCalories, absoluteTolerance = 0.01)
    }

    @Test
    fun `calculate uses correct MET at running speed boundary`() {
        val weightKg = 85.0
        val durationMins = 30
        val speedKmh = 7.9f

        val resultCalories = calorieCalculator.calculate(
            activityType = ActivityType.Running,
            averageSpeedMetersPerSecond = speedKmh.toMetersPerSecond(),
            weightKg = weightKg,
            durationMillis = durationMins.toMillis()
        )

        val expectedMet = 8.3
        val expectedCalories = expectedMet * weightKg * durationMins.toHours()

        assertEquals(expected = expectedCalories, actual = resultCalories, absoluteTolerance = 0.01)
    }

    @Test
    fun `calculate uses correct MET at cycling speed boundary`() {
        val weightKg = 85.0
        val durationMins = 30
        val speedKmh = 15.9f

        val resultCalories = calorieCalculator.calculate(
            activityType = ActivityType.Cycling,
            averageSpeedMetersPerSecond = speedKmh.toMetersPerSecond(),
            weightKg = weightKg,
            durationMillis = durationMins.toMillis()
        )

        val expectedMet = 4.0
        val expectedCalories = expectedMet * weightKg * durationMins.toHours()

        assertEquals(expected = expectedCalories, actual = resultCalories, absoluteTolerance = 0.01)
    }

    @Test
    fun `calculate returns zero calories when duration is zero`() {
        val speedKmh = 17f
        val resultCalories = calorieCalculator.calculate(
            activityType = ActivityType.Cycling,
            averageSpeedMetersPerSecond = speedKmh.toMetersPerSecond(),
            weightKg = 85.0,
            durationMillis = 0L // <-- Assuming zero duration
        )
        assertEquals(expected = 0.0, actual = resultCalories)
    }

    @Test
    fun `calculate scales linearly with weight`() {
        val weightKg1 = 65.0
        val durationMins = 30
        val speedKmh = 4f

        val result1 = calorieCalculator.calculate(
            activityType = ActivityType.Walking,
            averageSpeedMetersPerSecond = speedKmh.toMetersPerSecond(),
            weightKg = weightKg1,
            durationMillis = durationMins.toMillis()
        )

        val expectedMet = 2.8
        val expectedCalories = expectedMet * weightKg1 * durationMins.toHours()
        assertEquals(expected = expectedCalories, actual = result1, absoluteTolerance = 0.01)

        val weightKg2 = weightKg1 * 2 // Scaling weight1 2 times
        val result2 = calorieCalculator.calculate(
            activityType = ActivityType.Walking,
            averageSpeedMetersPerSecond = speedKmh.toMetersPerSecond(),
            weightKg = weightKg2,
            durationMillis = durationMins.toMillis()
        )
        // We expected the result2 becomes 2 times of result1
        assertEquals(expected = result1 * 2, actual = result2, absoluteTolerance = 0.01)
    }

    @Test
    fun `calculate scales linearly with duration`() {
        val weightKg = 85.0
        val durationMins1 = 30 // 30 minutes
        val speedKmh = 4f

        val result1 = calorieCalculator.calculate(
            activityType = ActivityType.Walking,
            averageSpeedMetersPerSecond = speedKmh.toMetersPerSecond(),
            weightKg = weightKg,
            durationMillis = durationMins1.toMillis()
        )

        val expectedMet = 2.8
        val expectedCalories = expectedMet * weightKg * durationMins1.toHours()
        assertEquals(expected = expectedCalories, actual = result1, absoluteTolerance = 0.01)

        val durationMins2 = durationMins1 * 2 // Scaling durationMins1 2 times (60 mins)
        val result2 = calorieCalculator.calculate(
            activityType = ActivityType.Walking,
            averageSpeedMetersPerSecond = speedKmh.toMetersPerSecond(),
            weightKg = weightKg,
            durationMillis = durationMins2.toMillis()
        )
        // We expected the result2 becomes 2 times of result1
        assertEquals(expected = result1 * 2, actual = result2, absoluteTolerance = 0.01)
    }

    // MET bands, copied by hand from the table in CalorieCalculator. Each
    // row is (boundary km/h, MET just below it, MET exactly at it). The bands use `<`, so a speed
    // exactly on a boundary already falls in the next band.
    @Test
    fun `walking uses the right MET just below and exactly at every band boundary`() {
        assertBandBoundaries(
            ActivityType.Walking,
            lowestBandMet = 2.0,
            boundaries = listOf(
                Boundary(kmh = 3.2, metBelow = 2.0, metAt = 2.8),
                Boundary(kmh = 4.5, metBelow = 2.8, metAt = 3.5),
                Boundary(kmh = 5.1, metBelow = 3.5, metAt = 4.3),
                Boundary(kmh = 5.6, metBelow = 4.3, metAt = 5.0),
                Boundary(kmh = 6.4, metBelow = 5.0, metAt = 7.0)
            )
        )
    }

    @Test
    fun `running uses the right MET just below and exactly at every band boundary`() {
        assertBandBoundaries(
            ActivityType.Running,
            lowestBandMet = 8.3,
            boundaries = listOf(
                Boundary(kmh = 8.0, metBelow = 8.3, metAt = 9.0),
                Boundary(kmh = 9.7, metBelow = 9.0, metAt = 9.8),
                Boundary(kmh = 10.8, metBelow = 9.8, metAt = 10.5),
                Boundary(kmh = 11.3, metBelow = 10.5, metAt = 11.0),
                Boundary(kmh = 12.1, metBelow = 11.0, metAt = 11.8),
                Boundary(kmh = 12.9, metBelow = 11.8, metAt = 12.8)
            )
        )
    }

    @Test
    fun `cycling uses the right MET just below and exactly at every band boundary`() {
        assertBandBoundaries(
            ActivityType.Cycling,
            lowestBandMet = 4.0,
            boundaries = listOf(
                Boundary(kmh = 16.0, metBelow = 4.0, metAt = 6.8),
                Boundary(kmh = 19.2, metBelow = 6.8, metAt = 8.0),
                Boundary(kmh = 22.4, metBelow = 8.0, metAt = 10.0),
                Boundary(kmh = 25.6, metBelow = 10.0, metAt = 12.0)
            )
        )
    }

    @Test
    fun `speeds that convert to a boundary exactly fall in the next band`() {
        // 1.25 m/s * 3.6 = 4.5 km/h and 3.0 m/s * 3.6 = 10.8 km/h with no rounding error, so these
        // two pin the `<` comparison itself: with `<=` they would stay in the lower band.
        assertEquals(3.5 * WEIGHT_KG, caloriesForOneHour(ActivityType.Walking, 1.25f), absoluteTolerance = TOLERANCE)
        assertEquals(10.5 * WEIGHT_KG, caloriesForOneHour(ActivityType.Running, 3.0f), absoluteTolerance = TOLERANCE)
    }

    private data class Boundary(val kmh: Double, val metBelow: Double, val metAt: Double)

    private fun assertBandBoundaries(activityType: ActivityType, lowestBandMet: Double, boundaries: List<Boundary>) {
        assertEquals(
            lowestBandMet * WEIGHT_KG,
            caloriesForOneHour(activityType, 0f),
            absoluteTolerance = TOLERANCE,
            message = "$activityType at 0 km/h"
        )
        boundaries.forEach { boundary ->
            val atSpeed = lowestSpeedAtOrAbove(boundary.kmh)
            assertEquals(
                boundary.metBelow * WEIGHT_KG,
                caloriesForOneHour(activityType, atSpeed.nextDown()),
                absoluteTolerance = TOLERANCE,
                message = "$activityType just below ${boundary.kmh} km/h"
            )
            assertEquals(
                boundary.metAt * WEIGHT_KG,
                caloriesForOneHour(activityType, atSpeed),
                absoluteTolerance = TOLERANCE,
                message = "$activityType at ${boundary.kmh} km/h"
            )
        }
    }

    // The calculator takes Float m/s and converts with `* 3.6` in Double. Most km/h boundaries have
    // no Float that converts to them exactly, so "at the boundary" is the smallest Float whose km/h
    // is >= the boundary, and "just below" is the Float right before it.
    private fun lowestSpeedAtOrAbove(kmh: Double): Float {
        var metersPerSecond = (kmh / 3.6).toFloat()
        while (metersPerSecond * 3.6 < kmh) metersPerSecond = metersPerSecond.nextUp()
        while (metersPerSecond.nextDown() * 3.6 >= kmh) metersPerSecond = metersPerSecond.nextDown()
        return metersPerSecond
    }

    // One hour at WEIGHT_KG, so the expected calories are simply MET * WEIGHT_KG.
    private fun caloriesForOneHour(activityType: ActivityType, metersPerSecond: Float): Double =
        calorieCalculator.calculate(
            activityType = activityType,
            averageSpeedMetersPerSecond = metersPerSecond,
            weightKg = WEIGHT_KG,
            durationMillis = 3_600_000L
        )

    private fun Float.toMetersPerSecond(): Float = this / 3.6f

    private fun Int.toMillis(): Long = this * 60_000L

    private fun Int.toHours(): Double = this / 60.0

    private companion object {
        const val WEIGHT_KG = 60.0
        const val TOLERANCE = 1e-9
    }
}
