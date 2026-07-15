package dev.roozbahani.trailmetrics.domain.util

interface Clock {
    fun nowMillis(): Long
}
