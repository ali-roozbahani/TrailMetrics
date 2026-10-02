package dev.roozbahani.trailmetrics.domain.usecase

import dev.roozbahani.trailmetrics.domain.fakes.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.model.ActivitiesUpdate
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class ObserveActivitiesUseCaseTest {

    private val activityHistoryRepository = FakeActivityHistoryRepository()
    private val useCase = ObserveActivitiesUseCase(activityHistoryRepository)

    @Test
    fun `invoke maps every emission to Loaded`() = runTest {
        activityHistoryRepository.activitiesFlow = flowOf(listOf(record(1)), listOf(record(1), record(2)))

        val updates = useCase().toList()

        assertEquals(
            listOf<ActivitiesUpdate>(
                ActivitiesUpdate.Loaded(listOf(record(1))),
                ActivitiesUpdate.Loaded(listOf(record(1), record(2)))
            ),
            updates
        )
    }

    @Test
    fun `invoke turns an upstream exception into one Failed and then completes`() = runTest {
        activityHistoryRepository.activitiesFlow = flow {
            emit(listOf(record(1)))
            throw IllegalStateException("database closed")
        }

        val updates = useCase().toList()

        assertEquals(
            listOf(ActivitiesUpdate.Loaded(listOf(record(1))), ActivitiesUpdate.Failed),
            updates
        )
    }

    @Test
    fun `invoke turns an exception thrown when calling the repository into one Failed and then completes`() = runTest {
        activityHistoryRepository.observeActivitiesCallFailure = IllegalStateException("thrown at call time")

        val updates = useCase().toList()

        assertEquals(listOf<ActivitiesUpdate>(ActivitiesUpdate.Failed), updates)
    }

    @Test
    fun `invoke does not catch an Error thrown when calling the repository`() = runTest {
        activityHistoryRepository.observeActivitiesCallFailure = AssertionError("not an Exception")

        assertFailsWith<AssertionError> { useCase().toList() }
    }

    @Test
    fun `invoke passes upstream cancellation through`() = runTest {
        activityHistoryRepository.activitiesFlow = flow { throw CancellationException("cancelled upstream") }

        val exception = assertFailsWith<CancellationException> { useCase().toList() }

        assertEquals("cancelled upstream", exception.message)
    }

    @Test
    fun `invoke emits no Failed when the collector is cancelled`() = runTest {
        activityHistoryRepository.activitiesFlow = flow {
            emit(listOf(record(1)))
            awaitCancellation()
        }
        val updates = mutableListOf<ActivitiesUpdate>()
        val collection = launch(start = CoroutineStart.UNDISPATCHED) { useCase().toList(updates) }

        collection.cancelAndJoin()

        assertTrue(collection.isCancelled)
        assertEquals(listOf<ActivitiesUpdate>(ActivitiesUpdate.Loaded(listOf(record(1)))), updates)
    }

    @Test
    fun `invoke does not catch an Error`() = runTest {
        activityHistoryRepository.activitiesFlow = flow { throw NotImplementedError("not an Exception") }

        assertFailsWith<NotImplementedError> { useCase().toList() }
    }

    private fun record(id: Long) = ActivityRecord(
        id = id,
        activityType = ActivityType.Running,
        startedAtEpochMillis = 1_000L,
        endedAtEpochMillis = 61_000L,
        distanceMeters = 250.0,
        durationMillis = 60_000L,
        averageSpeedMetersPerSecond = 4.2f,
        calories = 18.0,
        plannedRoutePoints = emptyList(),
        actualPath = emptyList(),
        snapshotFilePath = null
    )
}
