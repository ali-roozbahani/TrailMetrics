package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.TrackingEvent
import dev.roozbahani.trailmetrics.domain.model.TrackingMetrics
import dev.roozbahani.trailmetrics.domain.model.TrackingState
import dev.roozbahani.trailmetrics.domain.model.finishedState
import dev.roozbahani.trailmetrics.domain.model.millisSinceLastUpdate
import dev.roozbahani.trailmetrics.domain.model.pausedState
import dev.roozbahani.trailmetrics.domain.util.distanceTo

class UpdateTrackingStateUseCase {

    operator fun invoke(
        currentState: TrackingState,
        newEvent: TrackingEvent
    ): TrackingState {
        return when (newEvent) {
            is TrackingEvent.Start -> handleStart(currentState, newEvent)
            is TrackingEvent.Pause -> handlePause(currentState, newEvent)
            is TrackingEvent.Resume -> handleResume(currentState, newEvent)
            is TrackingEvent.Stop -> handleStop(currentState, newEvent)
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
                    lastUpdateElapsedRealtimeMillis = startEvent.elapsedRealtimeMillis,
                    distanceMeters = 0.0,
                    path = listOf(startEvent.startPoint)
                )
                TrackingState.Tracking(metrics)
            }

            is TrackingState.Tracking, is TrackingState.Paused -> currentState
        }
    }

    private fun handlePause(currentState: TrackingState, pauseEvent: TrackingEvent.Pause): TrackingState {
        return when (currentState) {
            is TrackingState.Tracking ->
                pausedState(currentState.metrics.accountedUntil(pauseEvent.elapsedRealtimeMillis))
            is TrackingState.Idle, is TrackingState.Paused, is TrackingState.Finished -> currentState
        }
    }

    private fun handleResume(
        currentState: TrackingState,
        resumeEvent: TrackingEvent.Resume
    ): TrackingState {
        return when (currentState) {
            is TrackingState.Paused -> TrackingState.Tracking(
                currentState.metrics.copy(
                    lastUpdateElapsedRealtimeMillis = resumeEvent.elapsedRealtimeMillis,
                    awaitingFirstFixAfterResume = true
                )
            )

            is TrackingState.Idle, is TrackingState.Tracking, is TrackingState.Finished -> currentState
        }
    }

    private fun handleStop(currentState: TrackingState, stopEvent: TrackingEvent.Stop): TrackingState {
        return when (currentState) {
            is TrackingState.Tracking ->
                finishedState(currentState.metrics.accountedUntil(stopEvent.elapsedRealtimeMillis))
            is TrackingState.Paused -> finishedState(currentState.metrics)
            is TrackingState.Idle, is TrackingState.Finished -> currentState
        }
    }

    private fun handleLocationReceived(
        currentState: TrackingState,
        newEvent: TrackingEvent.LocationReceived
    ): TrackingState {
        return when (currentState) {
            is TrackingState.Tracking -> {
                // The first fix after a Resume does not count the jump made while paused.
                val deltaDistance = if (currentState.metrics.awaitingFirstFixAfterResume) {
                    0.0
                } else {
                    currentState.metrics.path.last().distanceTo(newEvent.coordinates)
                }
                val newMetrics = currentState.metrics.copy(
                    elapsedMillis = currentState.metrics.elapsedMillis +
                        currentState.metrics.millisSinceLastUpdate(newEvent.elapsedRealtimeMillis),
                    lastUpdateElapsedRealtimeMillis = newEvent.elapsedRealtimeMillis,
                    distanceMeters = currentState.metrics.distanceMeters + deltaDistance,
                    path = currentState.metrics.path + newEvent.coordinates,
                    currentSpeedMetersPerSecond = newEvent.speedMetersPerSecond,
                    awaitingFirstFixAfterResume = false
                )

                TrackingState.Tracking(newMetrics)
            }

            is TrackingState.Idle, is TrackingState.Paused, is TrackingState.Finished -> currentState
        }
    }

    /**
     * The time from the last accounted update (a fix, a Start or a Resume) to [elapsedRealtimeMillis] of a Pause or
     * Stop counts as recorded time: the user was recording until then.
     */
    private fun TrackingMetrics.accountedUntil(elapsedRealtimeMillis: Long): TrackingMetrics = copy(
        elapsedMillis = elapsedMillis + millisSinceLastUpdate(elapsedRealtimeMillis),
        lastUpdateElapsedRealtimeMillis = maxOf(lastUpdateElapsedRealtimeMillis, elapsedRealtimeMillis)
    )
}
