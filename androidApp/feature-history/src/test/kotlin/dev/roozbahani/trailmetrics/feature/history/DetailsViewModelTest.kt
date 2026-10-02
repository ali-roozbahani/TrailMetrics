package dev.roozbahani.trailmetrics.feature.history

import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.feature.history.fakes.activityRecord
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.TestScope
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
    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.confirmDelete(viewModel: DetailsViewModel, snapshot: File): List<DeleteCompletion> {
        val completions = mutableListOf<DeleteCompletion>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.events.collect { event ->
                assertEquals(DetailsEvent.Deleted, event)
                completions += DeleteCompletion(activityHistoryRepository.deletedIds.toList(), snapshot.exists())
            }
        }
        viewModel.onAction(DetailsAction.DeleteConfirmed)
        return completions
    }

    @Test
    fun `state is loading until the activity is fetched`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST))
        val gate = CompletableDeferred<Unit>()
        activityHistoryRepository.getActivityGate = gate

        val viewModel = createViewModel(activityId = 1L)
        testScheduler.runCurrent()

        assertEquals(DetailsState(activity = null, isLoading = true), viewModel.state.value)

        gate.complete(Unit)
        testScheduler.runCurrent()

        assertEquals(DetailsState(activity = FIRST, isLoading = false), viewModel.state.value)
    }

    @Test
    fun `loads the activity with the given id`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST, SECOND))

        val viewModel = createViewModel(activityId = 2L)
        testScheduler.runCurrent()

        assertEquals(DetailsState(activity = SECOND, isLoading = false), viewModel.state.value)
        assertEquals(listOf(2L), activityHistoryRepository.requestedIds)
    }

    @Test
    fun `an unknown id stops loading with no activity`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST))

        val viewModel = createViewModel(activityId = 99L)
        testScheduler.runCurrent()

        assertEquals(DetailsState(activity = null, isLoading = false), viewModel.state.value)
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

            val completions = confirmDelete(viewModel, snapshot)
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

        val completions = confirmDelete(viewModel, snapshot)
        testScheduler.runCurrent()

        // The snapshot path is read from the loaded state, so nothing is known to delete yet.
        assertEquals(listOf(DeleteCompletion(deletedIds = listOf(1L), snapshotExists = true)), completions)
        assertTrue(snapshot.exists())
    }

    @Test
    fun `confirming delete for an unknown id still deletes the id and signals completion`() =
        runTest(testScheduler) {
            val otherSnapshot = tempFolder.newFile("snapshot-1.png")
            activityHistoryRepository.setActivities(
                listOf(activityRecord(id = 1L, snapshotFilePath = otherSnapshot.absolutePath))
            )
            val viewModel = createViewModel(activityId = 99L)
            testScheduler.runCurrent()

            val completions = confirmDelete(viewModel, otherSnapshot)
            testScheduler.runCurrent()

            assertEquals(listOf(DeleteCompletion(deletedIds = listOf(99L), snapshotExists = true)), completions)
            assertTrue(otherSnapshot.exists())
        }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    @Test
    fun `Deleted is buffered until a collector subscribes`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST))
        val viewModel = createViewModel(activityId = 1L)
        testScheduler.runCurrent()

        viewModel.onAction(DetailsAction.DeleteConfirmed)
        testScheduler.runCurrent()
        val events = mutableListOf<DetailsEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }
        testScheduler.runCurrent()

        assertEquals(listOf<DetailsEvent>(DetailsEvent.Deleted), events)
    }

    // Defect pinned as-is (BOARD.md `details-delete-confirmed-twice`): each Deleted pops the back
    // stack once, so a second confirmation would also leave the History screen.
    @Test
    fun `confirming delete twice currently deletes and signals completion twice`() = runTest(testScheduler) {
        val snapshot = tempFolder.newFile("snapshot-1.png")
        activityHistoryRepository.setActivities(
            listOf(activityRecord(id = 1L, snapshotFilePath = snapshot.absolutePath))
        )
        val viewModel = createViewModel(activityId = 1L)
        testScheduler.runCurrent()

        val completions = confirmDelete(viewModel, snapshot)
        viewModel.onAction(DetailsAction.DeleteConfirmed)
        testScheduler.runCurrent()

        assertEquals(
            listOf(
                DeleteCompletion(deletedIds = listOf(1L), snapshotExists = false),
                DeleteCompletion(deletedIds = listOf(1L, 1L), snapshotExists = false)
            ),
            completions
        )
    }

    @Test
    fun `state keeps the loaded activity after delete`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST))
        val viewModel = createViewModel(activityId = 1L)
        testScheduler.runCurrent()

        viewModel.onAction(DetailsAction.DeleteConfirmed)
        testScheduler.runCurrent()

        assertEquals(listOf(1L), activityHistoryRepository.deletedIds)
        assertEquals(DetailsState(activity = FIRST, isLoading = false), viewModel.state.value)
    }

    private companion object {
        val FIRST = activityRecord(id = 1L)
        val SECOND = activityRecord(id = 2L)
    }
}
