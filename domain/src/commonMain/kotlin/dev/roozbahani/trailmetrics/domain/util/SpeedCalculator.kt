package dev.roozbahani.trailmetrics.domain.util

import dev.roozbahani.trailmetrics.domain.model.Coordinates

class SpeedCalculator(
    private val windowSize: Int = 5,
    private val acceptableAccuracyMeters: Float = 20f
) {

    private val recentSamples = ArrayDeque<LocationSample>()

    fun calculate(
        coordinates: Coordinates,
        timestampMillis: Long,
        reportedSpeedMetersPerSecond: Float?,
        accuracyMeters: Float?
    ): Float? {
        recentSamples.addLast(LocationSample(coordinates, timestampMillis))
        if (recentSamples.size > windowSize) recentSamples.removeFirst()

        val isReported: Boolean = reportedSpeedMetersPerSecond != null &&
                accuracyMeters != null &&
                accuracyMeters <= acceptableAccuracyMeters

        return if (isReported) {
            reportedSpeedMetersPerSecond
        } else {
            calculateFromWindow()
        }
    }

    fun reset() {
        recentSamples.clear()
    }

    private fun calculateFromWindow(): Float? {
        if (recentSamples.size < 2) return null

        val first = recentSamples.first()
        val last = recentSamples.last()
        val distanceMeters: Double = first.coordinates.distanceTo(last.coordinates)
        val timeSeconds: Double = (last.timestampMillis - first.timestampMillis) / 1000.00
        return if (timeSeconds > 0) (distanceMeters / timeSeconds).toFloat() else null
    }
}

data class LocationSample(val coordinates: Coordinates, val timestampMillis: Long)
