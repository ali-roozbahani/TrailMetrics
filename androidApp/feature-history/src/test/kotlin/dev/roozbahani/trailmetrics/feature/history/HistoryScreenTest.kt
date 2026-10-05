package dev.roozbahani.trailmetrics.feature.history

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.usecase.ObserveActivitiesUseCase
import dev.roozbahani.trailmetrics.feature.history.di.historyUiModule
import dev.roozbahani.trailmetrics.feature.history.fakes.activityRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.koin.core.context.startKoin
import org.koin.core.context.stopKoin
import org.koin.dsl.module
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals

/**
 * [HistoryRoot] with the real [HistoryViewModel] from [historyUiModule], on a fake repository,
 * under Robolectric. Navigation lives in `androidApp/app`, so "opened details" is a call of
 * the `onActivityClicked` callback.
 */
@RunWith(RobolectricTestRunner::class)
// A phone-sized screen, so the LazyColumn composes both rows of the two-row tests.
@Config(sdk = [35], qualifiers = "w411dp-h891dp")
class HistoryScreenTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    private val testScheduler = TestCoroutineScheduler()
    private val activityHistoryRepository = FakeActivityHistoryRepository()
    private val robot = HistoryScreenRobot(composeRule)
    private val clickedActivityIds = mutableListOf<Long>()

    @OptIn(ExperimentalCoroutinesApi::class) // setMain/UnconfinedTestDispatcher have no stable replacement
    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        startKoin {
            modules(
                historyUiModule,
                module {
                    single<ActivityHistoryRepository> { activityHistoryRepository }
                    factory { ObserveActivitiesUseCase(activityHistoryRepository = get()) }
                }
            )
        }
    }

    @OptIn(ExperimentalCoroutinesApi::class) // resetMain has no stable replacement
    @After
    fun tearDown() {
        stopKoin()
        Dispatchers.resetMain()
    }

    private fun showHistory() = robot.setContent(onActivityClicked = { clickedActivityIds += it })

    @Test
    fun `shows a loading indicator until the activities arrive`() {
        showHistory().assertLoading()

        activityHistoryRepository.setActivities(listOf(RUN))

        robot.assertNotLoading().assertRowShown(RUN, CoreStrings.activity_type_running)
    }

    @Test
    fun `the empty state renders when there are no activities`() {
        activityHistoryRepository.setActivities(emptyList())

        showHistory()
            .assertNotLoading()
            .assertEmptyStateShown()
    }

    @Test
    fun `the list shows each activity's type and key values`() {
        activityHistoryRepository.setActivities(listOf(RUN, RIDE))

        showHistory()
            .assertEmptyStateNotShown()
            .assertRowShown(RUN, CoreStrings.activity_type_running)
            .assertRowShown(RIDE, CoreStrings.activity_type_cycling)
    }

    @Test
    fun `tapping a row opens its details`() {
        activityHistoryRepository.setActivities(listOf(RUN, RIDE))

        showHistory().clickRow(CoreStrings.activity_type_cycling)

        assertEquals(listOf(RIDE.id), clickedActivityIds)
    }

    @Test
    fun `confirming delete deletes the activity once and removes its row`() {
        activityHistoryRepository.setActivities(listOf(RUN))

        showHistory()
            .clickDelete()
            .assertDialogShown()
            .confirmDelete()
            .assertDialogClosed()
            .assertRowNotShown(RUN)
            .assertEmptyStateShown()

        assertEquals(listOf(RUN.id), activityHistoryRepository.deletedIds)
    }

    @Test
    fun `Cancel closes the dialog without deleting`() {
        activityHistoryRepository.setActivities(listOf(RUN))

        showHistory()
            .clickDelete()
            .cancelDelete()
            .assertDialogClosed()
            .assertRowShown(RUN, CoreStrings.activity_type_running)

        assertEquals(emptyList(), activityHistoryRepository.deletedIds)
    }

    @Test
    fun `a failed delete shows the error and keeps the row`() {
        activityHistoryRepository.setActivities(listOf(RUN))
        activityHistoryRepository.deleteActivityFailure = IllegalStateException("database locked")

        showHistory()
            .clickDelete()
            .confirmDelete()
            .assertErrorShown()
            .assertRowShown(RUN, CoreStrings.activity_type_running)

        assertEquals(emptyList(), activityHistoryRepository.deletedIds)
    }

    @Test
    fun `a failed read shows the error and stops the loading indicator`() {
        activityHistoryRepository.observeActivitiesFailure = IllegalStateException("database locked")

        showHistory()
            .assertNotLoading()
            .assertErrorShown()
    }

    private companion object {
        val RUN = activityRecord(id = 1L)
        val RIDE = activityRecord(id = 2L).copy(
            activityType = ActivityType.Cycling,
            startedAtEpochMillis = RUN.startedAtEpochMillis + 86_400_000L,
            durationMillis = 1_500_000L,
            calories = null
        )
    }
}
