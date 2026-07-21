package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.TrackingEvent
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.util.distanceTo

class UpdateTrackingStateUseCase {

    operator fun invoke(
        currentState: TrackingState,
        newEvent: TrackingEvent
    ): TrackingState {
        return when (newEvent) {
            is TrackingEvent.Start -> handleStart(currentState, newEvent)
            is TrackingEvent.Pause -> handlePause(currentState)
            is TrackingEvent.Resume -> handleResume(currentState, newEvent)
            is TrackingEvent.Stop -> handleStop(currentState)
            is TrackingEvent.LocationReceived -> handleLocationReceived(currentState, newEvent)
        }
    }

    private fun handleStart(
        currentState: TrackingState,
        startEvent: TrackingEvent.Start
    ): TrackingState {
        return when (currentState) {
            is TrackingState.Idle, is TrackingState.Finished -> {
                val metrics = TrackingMetrics(
                    elapsedMillis = 0,
                    lastUpdateTimestampMillis = startEvent.timestampMillis,
                    distanceMeters = 0.0,
                    path = listOf(startEvent.startPoint)
                )
                TrackingState.Tracking(metrics)
            }

            else -> currentState
        }
    }

    private fun handlePause(currentState: TrackingState): TrackingState {
        return when (currentState) {
            is TrackingState.Tracking -> TrackingState.Paused(currentState.metrics)
            else -> currentState
        }
    }

    private fun handleResume(
        currentState: TrackingState,
        resumeEvent: TrackingEvent.Resume
    ): TrackingState {
        return when (currentState) {
            is TrackingState.Paused -> TrackingState.Tracking(
                currentState.metrics.copy(
                    lastUpdateTimestampMillis = resumeEvent.timestampMillis
                )
            )

            else -> currentState
        }
    }

    private fun handleStop(currentState: TrackingState): TrackingState {
        return when (currentState) {
            is TrackingState.Tracking -> TrackingState.Finished(currentState.metrics)
            is TrackingState.Paused -> TrackingState.Finished(currentState.metrics)
            else -> currentState
        }
    }

    private fun handleLocationReceived(
        currentState: TrackingState,
        newEvent: TrackingEvent.LocationReceived
    ): TrackingState {
        return when (currentState) {
            is TrackingState.Tracking -> {
                val deltaDistance = currentState.metrics.path.last().distanceTo(newEvent.coordinates)
                val deltaTime = newEvent.timestampMillis - currentState.metrics.lastUpdateTimestampMillis

                val newMetrics = currentState.metrics.copy(
                    elapsedMillis = currentState.metrics.elapsedMillis + deltaTime,
                    lastUpdateTimestampMillis = newEvent.timestampMillis,
                    distanceMeters = currentState.metrics.distanceMeters + deltaDistance,
                    path = currentState.metrics.path + newEvent.coordinates
                )

                TrackingState.Tracking(newMetrics)
            }

            else -> currentState
        }
    }

}
