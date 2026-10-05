package dev.roozbahani.trailmetrics.feature.history.di

import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.usecase.ObserveActivitiesUseCase
import dev.roozbahani.trailmetrics.feature.history.DetailsState
import dev.roozbahani.trailmetrics.feature.history.DetailsViewModel
import dev.roozbahani.trailmetrics.feature.history.HistoryState
import dev.roozbahani.trailmetrics.feature.history.HistoryViewModel
import dev.roozbahani.trailmetrics.feature.history.fakes.activityRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.koin.core.parameter.parametersOf
import org.koin.dsl.koinApplication
import org.koin.dsl.module
import kotlin.test.assertEquals

class HistoryUiModuleTest {

    private val testScheduler = TestCoroutineScheduler()
    private val activityHistoryRepository = FakeActivityHistoryRepository()

    /** The bindings the app's other modules provide, built from a fake. */
    private val collaboratorsModule = module {
        single<ActivityHistoryRepository> { activityHistoryRepository }
        factory { ObserveActivitiesUseCase(activityHistoryRepository = get()) }
    }

    private val koin = koinApplication { modules(historyUiModule, collaboratorsModule) }.koin

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

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    @Test
    fun `historyUiModule builds HistoryViewModel on the provided repository`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST, SECOND))

        val viewModel = koin.get<HistoryViewModel>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect {} }
        testScheduler.runCurrent()

        assertEquals(HistoryState(activities = listOf(FIRST, SECOND), isLoading = false), viewModel.state.value)
    }

    @Test
    fun `historyUiModule builds DetailsViewModel for the activity id parameter`() = runTest(testScheduler) {
        activityHistoryRepository.setActivities(listOf(FIRST, SECOND))

        val viewModel = koin.get<DetailsViewModel> { parametersOf(2L) }
        testScheduler.runCurrent()

        assertEquals(DetailsState(activity = SECOND, isLoading = false), viewModel.state.value)
        assertEquals(listOf(2L), activityHistoryRepository.requestedIds)
    }

    private companion object {
        val FIRST = activityRecord(id = 1L)
        val SECOND = activityRecord(id = 2L)
    }
}
