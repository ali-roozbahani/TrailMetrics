package dev.roozbahani.trailmetrics.feature.history

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.usecase.ObserveActivitiesUseCase
import dev.roozbahani.trailmetrics.feature.history.di.historyUiModule
import dev.roozbahani.trailmetrics.feature.history.fakes.activityRecord
import kotlinx.coroutines.CompletableDeferred
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
 * [DetailsRoot] with the real [DetailsViewModel] from [historyUiModule], on a fake repository,
 * under Robolectric. Navigation lives in `androidApp/app`, so "navigated back" is a call of
 * the `onNavigateBack` callback.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DetailsScreenTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<ComponentActivity>()

    private val testScheduler = TestCoroutineScheduler()
    private val activityHistoryRepository = FakeActivityHistoryRepository()
    private val robot = DetailsScreenRobot(composeRule)
    private var navigateBackCalls = 0

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

    private fun showDetails(activityId: Long) =
        robot.setContent(activityId = activityId, onNavigateBack = { navigateBackCalls++ })

    @Test
    fun `shows the activity's metrics once loaded`() {
        activityHistoryRepository.setActivities(listOf(FIRST))

        showDetails(activityId = 1L)
            .assertNotLoading()
            .assertActivityShown(FIRST)
    }

    @Test
    fun `an unknown id shows not found`() {
        activityHistoryRepository.setActivities(listOf(FIRST))

        showDetails(activityId = 99L)
            .assertNotLoading()
            .assertNotFoundShown()
    }

    @Test
    fun `the back button navigates back`() {
        activityHistoryRepository.setActivities(listOf(FIRST))

        showDetails(activityId = 1L).clickBack()

        assertEquals(1, navigateBackCalls)
    }

    @Test
    fun `Cancel closes the dialog without deleting`() {
        activityHistoryRepository.setActivities(listOf(FIRST))

        showDetails(activityId = 1L)
            .clickDelete()
            .assertDialogShown()
            .cancelDelete()
            .assertDialogClosed()

        assertEquals(emptyList(), activityHistoryRepository.deletedIds)
        assertEquals(0, navigateBackCalls)
    }

    @Test
    fun `tapping Delete twice while the first delete is in flight deletes once and navigates back once`() {
        activityHistoryRepository.setActivities(listOf(FIRST))
        val deleteGate = CompletableDeferred<Unit>()
        activityHistoryRepository.deleteActivityGate = deleteGate

        showDetails(activityId = 1L)
            .clickDelete()
            .confirmDeleteTwice()
            .waitForIdle()

        // Both taps have reached the screen; the first delete is still suspended in the repository.
        assertEquals(emptyList(), activityHistoryRepository.deletedIds)
        assertEquals(0, navigateBackCalls)

        deleteGate.complete(Unit)
        robot.waitForIdle()

        assertEquals(listOf(1L), activityHistoryRepository.deletedIds)
        assertEquals(1, navigateBackCalls)
    }

    @Test
    fun `a failed delete shows the error and does not navigate back`() {
        activityHistoryRepository.setActivities(listOf(FIRST))
        activityHistoryRepository.deleteActivityFailure = IllegalStateException("database locked")

        showDetails(activityId = 1L)
            .clickDelete()
            .confirmDelete()
            .assertErrorShown()
            .assertActivityShown(FIRST)

        assertEquals(emptyList(), activityHistoryRepository.deletedIds)
        assertEquals(0, navigateBackCalls)
    }

    @Test
    fun `a failed load shows the error and stops the loading indicator`() {
        activityHistoryRepository.setActivities(listOf(FIRST))
        val loadGate = CompletableDeferred<Unit>()
        activityHistoryRepository.getActivityGate = loadGate
        activityHistoryRepository.getActivityFailure = IllegalStateException("database locked")

        showDetails(activityId = 1L).assertLoading()

        loadGate.complete(Unit)

        robot.waitForIdle()
            .assertNotLoading()
            .assertErrorShown()
            .assertNotFoundShown()
    }

    @Test
    fun `a delete retried while the error of the failed delete is shown navigates back at once`() {
        activityHistoryRepository.setActivities(listOf(FIRST))
        activityHistoryRepository.deleteActivityFailure = IllegalStateException("database locked")
        showDetails(activityId = 1L)
            .clickDelete()
            .confirmDelete()
            .assertErrorShown()

        activityHistoryRepository.deleteActivityFailure = null
        robot.clickDelete().confirmDelete().waitForIdle()

        // The test clock has not passed the snackbar's duration: the error is still shown.
        robot.assertErrorShown()
        assertEquals(listOf(1L), activityHistoryRepository.deletedIds)
        assertEquals(1, navigateBackCalls, "Deleted is handled while the error is shown")
    }

    @Test
    fun `two failed deletes in a row show their errors one after the other`() {
        activityHistoryRepository.setActivities(listOf(FIRST))
        activityHistoryRepository.deleteActivityFailure = IllegalStateException("database locked")

        // Both errors have the same text (every Details error is the general one), so the order
        // can't be seen here; that none is dropped and they come one at a time can.
        showDetails(activityId = 1L)
            .clickDelete()
            .confirmDelete()
            .clickDelete()
            .confirmDelete()
            .assertOneErrorShown()
            .waitForSnackbarToHide()
            .assertOneErrorShown()
            .waitForSnackbarToHide()
            .assertErrorNotShown()
    }

    private companion object {
        val FIRST = activityRecord(id = 1L)
    }
}
