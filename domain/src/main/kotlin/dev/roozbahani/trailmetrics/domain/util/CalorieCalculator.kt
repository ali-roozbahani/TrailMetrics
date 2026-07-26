package dev.roozbahani.trailmetrics.domain.util

import dev.roozbahani.trailmetrics.domain.model.ActivityType

class CalorieCalculator {

    fun calculate(
        activityType: ActivityType,
        averageSpeedMetersPerSecond: Float,
        weightKg: Double,
        durationMillis: Long
    ): Double {
        val met = metFor(activityType, averageSpeedMetersPerSecond)
        val durationHours: Double = durationMillis / 3_600_000.0
        return met * weightKg * durationHours
    }

    private fun metFor(activityType: ActivityType, speedMetersPerSecond: Float): Double {
        val speedKmh: Double = speedMetersPerSecond * 3.6
        return when (activityType) {
            ActivityType.Walking -> when {
                speedKmh < 3.2 -> 2.0
                speedKmh < 4.5 -> 2.8
                speedKmh < 5.1 -> 3.5
                speedKmh < 5.6 -> 4.3
                speedKmh < 6.4 -> 5.0
                else -> 7.0
            }

            ActivityType.Running -> when {
                speedKmh < 8.0 -> 8.3
                speedKmh < 9.7 -> 9.0
                speedKmh < 10.8 -> 9.8
                speedKmh < 11.3 -> 10.5
                speedKmh < 12.1 -> 11.0
                speedKmh < 12.9 -> 11.8
                else -> 12.8
            }

            ActivityType.Cycling -> when {
                speedKmh < 16.0 -> 4.0
                speedKmh < 19.2 -> 6.8
                speedKmh < 22.4 -> 8.0
                speedKmh < 25.6 -> 10.0
                else -> 12.0
            }
        }
    }
}
