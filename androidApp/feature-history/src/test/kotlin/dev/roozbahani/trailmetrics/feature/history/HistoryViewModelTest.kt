package dev.roozbahani.trailmetrics.feature.history

import dev.roozbahani.trailmetrics.core.error.RouteUiError
import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.usecase.ObserveActivitiesUseCase
import dev.roozbahani.trailmetrics.feature.history.fakes.activityRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
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
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HistoryViewModelTest {

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

    private fun createViewModel() = HistoryViewModel(
        activityHistoryRepository = activityHistoryRepository,
        observeActivitiesUseCase = ObserveActivitiesUseCase(activityHistoryRepository)
    )

    // The state is stateIn(WhileSubscribed): keep a subscriber for the whole test.
    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.subscribe(viewModel: HistoryViewModel): Job =
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect {} }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.collectEvents(viewModel: HistoryViewModel): List<HistoryEvent> {
        val events = mutableListOf<HistoryEvent>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.events.toList(events) }
        return events
    }

    @Test
    fun `state is loading until the repository emits`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        subscribe(viewModel)
        testScheduler.runCurrent()

        assertEquals(HistoryState(activities = emptyList(), isLoading = true), viewModel.state.value)
        assertFalse(viewModel.state.value.isEmpty)
    }

    @Test
    fun `emitted activities replace loading with the list in repository order`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        subscribe(viewModel)
        activityHistoryRepository.setActivities(listOf(FIRST, SECOND))
        testScheduler.runCurrent()

        assertEquals(HistoryState(activities = listOf(FIRST, SECOND), isLoading = false), viewModel.state.value)
        assertFalse(viewModel.state.value.isEmpty)
    }

    @Test
    fun `an empty list stops loading and is shown as empty`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        subscribe(viewModel)
        activityHistoryRepository.setActivities(emptyList())
        testScheduler.runCurrent()

        assertEquals(HistoryState(activities = emptyList(), isLoading = false), viewModel.state.value)
        assertTrue(viewModel.state.value.isEmpty)
    }

    @Test
    fun `state follows later repository emissions`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        subscribe(viewModel)
        activityHistoryRepository.setActivities(listOf(FIRST))
        testScheduler.runCurrent()
        activityHistoryRepository.setActivities(listOf(FIRST, SECOND))
        testScheduler.runCurrent()

        assertEquals(listOf(FIRST, SECOND), viewModel.state.value.activities)
    }

    @Test
    fun `deleting an activity removes the record and its snapshot file`() = runTest(testScheduler) {
        val snapshot = tempFolder.newFile("snapshot-1.png")
        val withSnapshot = activityRecord(id = 1L, snapshotFilePath = snapshot.absolutePath)
        activityHistoryRepository.setActivities(listOf(withSnapshot, SECOND))
        val viewModel = createViewModel()
        subscribe(viewModel)
        testScheduler.runCurrent()

        viewModel.onAction(HistoryAction.DeleteConfirmed(withSnapshot))
        testScheduler.runCurrent()

        assertEquals(listOf(1L), activityHistoryRepository.deletedIds)
        assertFalse(snapshot.exists())
        assertEquals(HistoryState(activities = listOf(SECOND), isLoading = false), viewModel.state.value)
    }

    @Test
    fun `deleting the last activity leaves the list empty`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST))
        val viewModel = createViewModel()
        subscribe(viewModel)
        testScheduler.runCurrent()

        viewModel.onAction(HistoryAction.DeleteConfirmed(FIRST))
        testScheduler.runCurrent()

        assertEquals(listOf(1L), activityHistoryRepository.deletedIds)
        assertTrue(viewModel.state.value.isEmpty)
    }

    @Test
    fun `deleting an activity without a snapshot removes only the record`() = runTest(testScheduler) {
        val unrelatedFile = tempFolder.newFile("unrelated.png")
        activityHistoryRepository.setActivities(listOf(FIRST, SECOND))
        val viewModel = createViewModel()
        subscribe(viewModel)
        testScheduler.runCurrent()

        viewModel.onAction(HistoryAction.DeleteConfirmed(SECOND))
        testScheduler.runCurrent()

        assertEquals(listOf(2L), activityHistoryRepository.deletedIds)
        assertTrue(unrelatedFile.exists())
        assertEquals(listOf(FIRST), viewModel.state.value.activities)
    }

    @Test
    fun `state is loading before anyone subscribes even when the repository has activities`() =
        runTest(testScheduler) {
            activityHistoryRepository.setActivities(listOf(FIRST, SECOND))
            val viewModel = createViewModel()
            testScheduler.runCurrent()

            assertEquals(HistoryState(activities = emptyList(), isLoading = true), viewModel.state.value)
        }

    @OptIn(ExperimentalCoroutinesApi::class) // advanceTimeBy has no stable replacement
    @Test
    fun `state keeps following the repository for five seconds after the last subscriber leaves`() =
        runTest(testScheduler) {
            activityHistoryRepository.setActivities(listOf(FIRST))
            val viewModel = createViewModel()
            val subscriber = subscribe(viewModel)
            testScheduler.runCurrent()
            subscriber.cancel()

            testScheduler.advanceTimeBy(STATE_STOP_TIMEOUT_MILLIS - 1)
            testScheduler.runCurrent()
            activityHistoryRepository.setActivities(listOf(FIRST, SECOND))
            testScheduler.runCurrent()

            assertEquals(listOf(FIRST, SECOND), viewModel.state.value.activities)
        }

    @OptIn(ExperimentalCoroutinesApi::class) // advanceTimeBy has no stable replacement
    @Test
    fun `state stops following the repository five seconds after the last subscriber leaves`() =
        runTest(testScheduler) {
            activityHistoryRepository.setActivities(listOf(FIRST))
            val viewModel = createViewModel()
            val subscriber = subscribe(viewModel)
            testScheduler.runCurrent()
            subscriber.cancel()

            testScheduler.advanceTimeBy(STATE_STOP_TIMEOUT_MILLIS)
            testScheduler.runCurrent()
            activityHistoryRepository.setActivities(listOf(FIRST, SECOND))
            testScheduler.runCurrent()

            assertEquals(listOf(FIRST), viewModel.state.value.activities)
        }

    @Test
    fun `deleting an activity that is not in the list still deletes its id and leaves the list unchanged`() =
        runTest(testScheduler) {
            activityHistoryRepository.setActivities(listOf(FIRST, SECOND))
            val viewModel = createViewModel()
            subscribe(viewModel)
            testScheduler.runCurrent()

            viewModel.onAction(HistoryAction.DeleteConfirmed(activityRecord(id = 99L)))
            testScheduler.runCurrent()

            assertEquals(listOf(99L), activityHistoryRepository.deletedIds)
            assertEquals(HistoryState(activities = listOf(FIRST, SECOND), isLoading = false), viewModel.state.value)
        }

    @Test
    fun `a failing delete emits a general ShowError and keeps the record and its snapshot file`() =
        runTest(testScheduler) {
            val snapshot = tempFolder.newFile("snapshot-1.png")
            val withSnapshot = activityRecord(id = 1L, snapshotFilePath = snapshot.absolutePath)
            activityHistoryRepository.setActivities(listOf(withSnapshot, SECOND))
            val viewModel = createViewModel()
            subscribe(viewModel)
            val events = collectEvents(viewModel)
            testScheduler.runCurrent()
            activityHistoryRepository.deleteActivityFailure = IllegalStateException("database locked")

            viewModel.onAction(HistoryAction.DeleteConfirmed(withSnapshot))
            testScheduler.runCurrent()

            assertEquals(listOf<HistoryEvent>(HistoryEvent.ShowError(RouteUiError.General)), events)
            assertEquals(emptyList(), activityHistoryRepository.deletedIds)
            assertTrue(snapshot.exists())
            assertEquals(listOf(withSnapshot, SECOND), viewModel.state.value.activities)
        }

    @Test
    fun `a failing activity list stops loading and emits a general ShowError`() = runTest(testScheduler) {
        activityHistoryRepository.observeActivitiesFailure = IllegalStateException("database locked")
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)
        subscribe(viewModel)
        testScheduler.runCurrent()

        assertEquals(HistoryState(activities = emptyList(), isLoading = false), viewModel.state.value)
        assertEquals(listOf<HistoryEvent>(HistoryEvent.ShowError(RouteUiError.General)), events)
    }

    @Test
    fun `deleting an activity whose snapshot path is blank removes only the record`() = runTest(testScheduler) {
        val blankPath = activityRecord(id = 1L, snapshotFilePath = "  ")
        activityHistoryRepository.setActivities(listOf(blankPath, SECOND))
        val viewModel = createViewModel()
        subscribe(viewModel)
        testScheduler.runCurrent()

        viewModel.onAction(HistoryAction.DeleteConfirmed(blankPath))
        testScheduler.runCurrent()

        assertEquals(listOf(1L), activityHistoryRepository.deletedIds)
        assertEquals(listOf(SECOND), viewModel.state.value.activities)
    }

    @Test
    fun `deleting an activity whose snapshot file no longer exists still removes the record`() =
        runTest(testScheduler) {
            val missingPath = File(tempFolder.root, "missing.png").absolutePath
            val withMissingSnapshot = activityRecord(id = 1L, snapshotFilePath = missingPath)
            activityHistoryRepository.setActivities(listOf(withMissingSnapshot, SECOND))
            val viewModel = createViewModel()
            subscribe(viewModel)
            testScheduler.runCurrent()

            viewModel.onAction(HistoryAction.DeleteConfirmed(withMissingSnapshot))
            testScheduler.runCurrent()

            assertEquals(listOf(1L), activityHistoryRepository.deletedIds)
            assertEquals(listOf(SECOND), viewModel.state.value.activities)
        }

    // New Action/Event surface with no pre-migration counterpart: the row click used to call
    // the screen's callback directly and never reached the ViewModel.
    @Test
    fun `clicking an activity emits NavigateToDetails with its id`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        val events = collectEvents(viewModel)

        viewModel.onAction(HistoryAction.ActivityClicked(activityId = 2L))
        testScheduler.runCurrent()

        assertEquals(listOf<HistoryEvent>(HistoryEvent.NavigateToDetails(activityId = 2L)), events)
    }

    @Test
    fun `clicks before anyone collects are delivered in order once a collector subscribes`() =
        runTest(testScheduler) {
            val viewModel = createViewModel()

            viewModel.onAction(HistoryAction.ActivityClicked(activityId = 3L))
            viewModel.onAction(HistoryAction.ActivityClicked(activityId = 1L))
            viewModel.onAction(HistoryAction.ActivityClicked(activityId = 2L))
            testScheduler.runCurrent()
            val events = collectEvents(viewModel)
            testScheduler.runCurrent()

            assertEquals(
                listOf<HistoryEvent>(
                    HistoryEvent.NavigateToDetails(activityId = 3L),
                    HistoryEvent.NavigateToDetails(activityId = 1L),
                    HistoryEvent.NavigateToDetails(activityId = 2L)
                ),
                events
            )
        }

    private companion object {
        const val STATE_STOP_TIMEOUT_MILLIS = 5_000L
        val FIRST = activityRecord(id = 1L)
        val SECOND = activityRecord(id = 2L)
    }
}
