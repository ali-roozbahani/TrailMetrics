package dev.roozbahani.trailmetrics.feature.history

import dev.roozbahani.trailmetrics.feature.history.fakes.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.feature.history.fakes.activityRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
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

    private fun createViewModel() = HistoryViewModel(activityHistoryRepository = activityHistoryRepository)

    // The state is stateIn(WhileSubscribed): keep a subscriber for the whole test.
    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.subscribe(viewModel: HistoryViewModel) {
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.uiState.collect {} }
    }

    @Test
    fun `state is loading until the repository emits`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        subscribe(viewModel)
        testScheduler.runCurrent()

        assertEquals(HistoryUiState(activities = emptyList(), isLoading = true), viewModel.uiState.value)
        assertFalse(viewModel.uiState.value.isEmpty)
    }

    @Test
    fun `emitted activities replace loading with the list in repository order`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        subscribe(viewModel)
        activityHistoryRepository.setActivities(listOf(FIRST, SECOND))
        testScheduler.runCurrent()

        assertEquals(HistoryUiState(activities = listOf(FIRST, SECOND), isLoading = false), viewModel.uiState.value)
        assertFalse(viewModel.uiState.value.isEmpty)
    }

    @Test
    fun `an empty list stops loading and is shown as empty`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        subscribe(viewModel)
        activityHistoryRepository.setActivities(emptyList())
        testScheduler.runCurrent()

        assertEquals(HistoryUiState(activities = emptyList(), isLoading = false), viewModel.uiState.value)
        assertTrue(viewModel.uiState.value.isEmpty)
    }

    @Test
    fun `state follows later repository emissions`() = runTest(testScheduler) {
        val viewModel = createViewModel()
        subscribe(viewModel)
        activityHistoryRepository.setActivities(listOf(FIRST))
        testScheduler.runCurrent()
        activityHistoryRepository.setActivities(listOf(FIRST, SECOND))
        testScheduler.runCurrent()

        assertEquals(listOf(FIRST, SECOND), viewModel.uiState.value.activities)
    }

    @Test
    fun `deleting an activity removes the record and its snapshot file`() = runTest(testScheduler) {
        val snapshot = tempFolder.newFile("snapshot-1.png")
        val withSnapshot = activityRecord(id = 1L, snapshotFilePath = snapshot.absolutePath)
        activityHistoryRepository.setActivities(listOf(withSnapshot, SECOND))
        val viewModel = createViewModel()
        subscribe(viewModel)
        testScheduler.runCurrent()

        viewModel.onDeleteActivity(withSnapshot)
        testScheduler.runCurrent()

        assertEquals(listOf(1L), activityHistoryRepository.deletedIds)
        assertFalse(snapshot.exists())
        assertEquals(HistoryUiState(activities = listOf(SECOND), isLoading = false), viewModel.uiState.value)
    }

    @Test
    fun `deleting the last activity leaves the list empty`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST))
        val viewModel = createViewModel()
        subscribe(viewModel)
        testScheduler.runCurrent()

        viewModel.onDeleteActivity(FIRST)
        testScheduler.runCurrent()

        assertEquals(listOf(1L), activityHistoryRepository.deletedIds)
        assertTrue(viewModel.uiState.value.isEmpty)
    }

    @Test
    fun `deleting an activity without a snapshot removes only the record`() = runTest(testScheduler) {
        val unrelatedFile = tempFolder.newFile("unrelated.png")
        activityHistoryRepository.setActivities(listOf(FIRST, SECOND))
        val viewModel = createViewModel()
        subscribe(viewModel)
        testScheduler.runCurrent()

        viewModel.onDeleteActivity(SECOND)
        testScheduler.runCurrent()

        assertEquals(listOf(2L), activityHistoryRepository.deletedIds)
        assertTrue(unrelatedFile.exists())
        assertEquals(listOf(FIRST), viewModel.uiState.value.activities)
    }

    private companion object {
        val FIRST = activityRecord(id = 1L)
        val SECOND = activityRecord(id = 2L)
    }
}
