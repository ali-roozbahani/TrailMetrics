package dev.roozbahani.trailmetrics.feature.history

import dev.roozbahani.trailmetrics.feature.history.fakes.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.feature.history.fakes.activityRecord
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DetailsViewModelTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    private val testScheduler = TestCoroutineScheduler()

    private val activityHistoryRepository = FakeActivityHistoryRepository()

    @OptIn(ExperimentalCoroutinesApi::class) // setMain/UnconfinedTestDispatcher have no stable replacement
    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
    }

    @OptIn(ExperimentalCoroutinesApi::class) // resetMain has no stable replacement
    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createViewModel(activityId: Long) = DetailsViewModel(
        activityId = activityId,
        activityHistoryRepository = activityHistoryRepository
    )

    /** What the repository and the file system looked like at the moment completion was signalled. */
    private data class DeleteCompletion(val deletedIds: List<Long>, val snapshotExists: Boolean)

    /** Confirms deletion and records every completion signal. */
    private fun DetailsViewModel.confirmDelete(snapshot: File): List<DeleteCompletion> {
        val completions = mutableListOf<DeleteCompletion>()
        onDeleteConfirmed(
            onDeleted = {
                completions += DeleteCompletion(activityHistoryRepository.deletedIds.toList(), snapshot.exists())
            }
        )
        return completions
    }

    @Test
    fun `state is loading until the activity is fetched`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST))
        val gate = CompletableDeferred<Unit>()
        activityHistoryRepository.getActivityGate = gate

        val viewModel = createViewModel(activityId = 1L)
        testScheduler.runCurrent()

        assertEquals(DetailsUiState(activity = null, isLoading = true), viewModel.uiState.value)

        gate.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(DetailsUiState(activity = FIRST, isLoading = false), viewModel.uiState.value)
    }

    @Test
    fun `loads the activity with the given id`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST, SECOND))

        val viewModel = createViewModel(activityId = 2L)
        testScheduler.runCurrent()

        assertEquals(DetailsUiState(activity = SECOND, isLoading = false), viewModel.uiState.value)
        assertEquals(listOf(2L), activityHistoryRepository.requestedIds)
    }

    @Test
    fun `an unknown id stops loading with no activity`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST))

        val viewModel = createViewModel(activityId = 99L)
        testScheduler.runCurrent()

        assertEquals(DetailsUiState(activity = null, isLoading = false), viewModel.uiState.value)
    }

    @Test
    fun `confirming delete removes the record and snapshot, then signals completion exactly once`() =
        runTest(testScheduler) {
            val snapshot = tempFolder.newFile("snapshot-1.png")
            activityHistoryRepository.setActivities(
                listOf(activityRecord(id = 1L, snapshotFilePath = snapshot.absolutePath), SECOND)
            )
            val viewModel = createViewModel(activityId = 1L)
            testScheduler.runCurrent()
            val deleteGate = CompletableDeferred<Unit>()
            activityHistoryRepository.deleteActivityGate = deleteGate

            val completions = viewModel.confirmDelete(snapshot)
            testScheduler.runCurrent()

            // Nothing is signalled while the record deletion is still in flight.
            assertEquals(emptyList(), completions)
            assertTrue(snapshot.exists())

            deleteGate.complete(Unit)
            testScheduler.advanceUntilIdle()

            assertEquals(listOf(DeleteCompletion(deletedIds = listOf(1L), snapshotExists = false)), completions)
            assertEquals(listOf(1L), activityHistoryRepository.deletedIds)
        }

    @Test
    fun `confirming delete before the activity has loaded keeps the snapshot file`() = runTest(testScheduler) {
        val snapshot = tempFolder.newFile("snapshot-1.png")
        activityHistoryRepository.setActivities(
            listOf(activityRecord(id = 1L, snapshotFilePath = snapshot.absolutePath))
        )
        activityHistoryRepository.getActivityGate = CompletableDeferred()
        val viewModel = createViewModel(activityId = 1L)
        testScheduler.runCurrent()

        val completions = viewModel.confirmDelete(snapshot)
        testScheduler.runCurrent()

        // The snapshot path is read from the loaded state, so nothing is known to delete yet.
        assertEquals(listOf(DeleteCompletion(deletedIds = listOf(1L), snapshotExists = true)), completions)
        assertTrue(snapshot.exists())
    }

    private companion object {
        val FIRST = activityRecord(id = 1L)
        val SECOND = activityRecord(id = 2L)
    }
}
