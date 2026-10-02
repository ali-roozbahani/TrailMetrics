package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.ActivitiesUpdate
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import kotlin.coroutines.cancellation.CancellationException

/**
 * [ActivityHistoryRepository.observeActivities] with its failure turned into a value.
 *
 * `@Throws` does not apply to a `Flow`, and SKIE's Swift flow iterator calls `fatalError` on
 * any error other than cancellation, so a failing repository flow would terminate the iOS app.
 * This use case catches an upstream [Exception] (never an `Error`, never cancellation) and
 * emits one [ActivitiesUpdate.Failed], after which the flow completes.
 */
class ObserveActivitiesUseCase(
    private val activityHistoryRepository: ActivityHistoryRepository
) {
    operator fun invoke(): Flow<ActivitiesUpdate> =
        activityHistoryRepository.observeActivities()
            .map<_, ActivitiesUpdate> { activities -> ActivitiesUpdate.Loaded(activities) }
            .catch { cause ->
                if (cause !is Exception || cause is CancellationException) throw cause
                emit(ActivitiesUpdate.Failed)
            }
}
