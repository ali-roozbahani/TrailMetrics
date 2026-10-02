package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.model.ActivitiesUpdate
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import kotlin.coroutines.cancellation.CancellationException

/**
 * [ActivityHistoryRepository.observeActivities] with its failure turned into a value.
 *
 * `@Throws` does not apply to a `Flow`, and SKIE's Swift flow iterator calls `fatalError` on
 * any error other than cancellation, so a failing repository flow would terminate the iOS app.
 * This use case catches an [Exception] (never an `Error`, never cancellation), whether the
 * repository throws it when `observeActivities()` is called or while the flow is collected,
 * and emits one [ActivitiesUpdate.Failed], after which the flow completes. `invoke()` itself
 * never throws: the repository is called only once the returned flow is collected.
 */
class ObserveActivitiesUseCase(
    private val activityHistoryRepository: ActivityHistoryRepository
) {
    operator fun invoke(): Flow<ActivitiesUpdate> =
        flow<ActivitiesUpdate> {
            emitAll(activityHistoryRepository.observeActivities().map { ActivitiesUpdate.Loaded(it) })
        }.catch { cause ->
            if (cause !is Exception || cause is CancellationException) throw cause
            emit(ActivitiesUpdate.Failed)
        }
}
