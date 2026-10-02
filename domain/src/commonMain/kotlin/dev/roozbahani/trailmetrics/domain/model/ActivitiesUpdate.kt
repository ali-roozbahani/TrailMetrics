package dev.roozbahani.trailmetrics.domain.model

/**
 * One emission of [dev.roozbahani.trailmetrics.domain.usecase.ObserveActivitiesUseCase]: the
 * current activity list, or the failure that ended the observation.
 */
sealed interface ActivitiesUpdate {
    data class Loaded(val activities: List<ActivityRecord>) : ActivitiesUpdate

    /** The activity list could not be read. The flow completes after this emission. */
    data object Failed : ActivitiesUpdate
}
