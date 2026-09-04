package dev.roozbahani.trailmetrics.domain.util

import dev.roozbahani.trailmetrics.domain.model.ActivityType
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

    private fun Float.toMetersPerSecond(): Float = this / 3.6f

    private fun Int.toMillis(): Long = this * 60_000L

    private fun Int.toHours(): Double = this / 60.0
}
