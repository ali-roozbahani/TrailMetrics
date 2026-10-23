package dev.roozbahani.trailmetrics.feature.tracking

import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import dev.roozbahani.trailmetrics.core.testing.FakeActivityHistoryRepository
import dev.roozbahani.trailmetrics.core.testing.FakeLocationRepository
import dev.roozbahani.trailmetrics.core.testing.FakeUserProfileRepository
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.UserProfile
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.usecase.UpdateTrackingStateUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.SpeedCalculator
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeClock
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeLogger
import dev.roozbahani.trailmetrics.feature.tracking.fakes.FakeTrackingServiceLauncher
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.StandardTestDispatcher
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

/**
 * The ViewModel owns the lifecycle of the snapshot files the screen produces: a file no saved
 * activity references is deleted, whatever the reason. [filesDir] stands in for the app's `filesDir`
 * and every test counts the files left in it.
 */
class TrackingViewModelSnapshotFileTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private val testScheduler = TestCoroutineScheduler()
    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private var ioDispatcher: CoroutineDispatcher = UnconfinedTestDispatcher(testScheduler)
    private val locationRepository = FakeLocationRepository()
    private val clock = FakeClock(nowMillis = 1_000_000L, elapsedRealtimeMillis = 5_000L)
    private val userProfileRepository = FakeUserProfileRepository()
    private val activityHistoryRepository = FakeActivityHistoryRepository()
    private val viewModelStore = ViewModelStore()
    private lateinit var filesDir: File

    @OptIn(ExperimentalCoroutinesApi::class) // setMain/UnconfinedTestDispatcher have no stable replacement
    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        filesDir = temporaryFolder.newFolder("files")
        userProfileRepository.userProfile = UserProfile(weightKg = 70.0)
    }

    @OptIn(ExperimentalCoroutinesApi::class) // resetMain has no stable replacement
    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @OptIn(ExperimentalCoroutinesApi::class) // UnconfinedTestDispatcher has no stable replacement
    private fun TestScope.createFinishedSession(): TrackingViewModel {
        val sessionManager = TrackingSessionManager(
            locationRepository = locationRepository,
            updateTrackingStateUseCase = UpdateTrackingStateUseCase(),
            trackingServiceLauncher = FakeTrackingServiceLauncher(),
            speedCalculator = SpeedCalculator(),
            clock = clock,
            logger = FakeLogger(),
            scope = backgroundScope
        )
        val viewModel = ViewModelProvider.create(viewModelStore, viewModelFactory {
            initializer {
                TrackingViewModel(
                    trackingSessionManager = sessionManager,
                    userProfileRepository = userProfileRepository,
                    calorieCalculator = CalorieCalculator(),
                    saveActivityUseCase = SaveActivityUseCase(activityHistoryRepository, CalorieCalculator(), clock),
                    activityType = ActivityType.Cycling,
                    plannedRoutePoints = emptyList(),
                    clock = clock,
                    ioDispatcher = ioDispatcher
                )
            }
        })[TrackingViewModel::class]
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { viewModel.state.collect {} }
        testScheduler.runCurrent()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()
        viewModel.onAction(TrackingAction.Stop)
        testScheduler.runCurrent()
        return viewModel
    }

    private fun newSnapshotFile(): String = File.createTempFile("activity_", ".png", filesDir).absolutePath

    private fun filesInDir(): List<String> = filesDir.listFiles().orEmpty().map { it.absolutePath }.sorted()

    private fun TestScope.finish(viewModel: TrackingViewModel, path: String?) {
        viewModel.onAction(TrackingAction.Finish(path))
        testScheduler.runCurrent()
    }

    @Test
    fun `the normal single save keeps its snapshot file and the activity references it`() =
        runTest(testScheduler) {
            val viewModel = createFinishedSession()
            val file = newSnapshotFile()

            finish(viewModel, file)

            assertEquals(listOf(file), filesInDir())
            assertEquals(file, activityHistoryRepository.savedActivities.single().snapshotFilePath)
        }

    @Test
    fun `a Finish during a slow save deletes its own file and keeps the one being saved`() =
        runTest(testScheduler) {
            val viewModel = createFinishedSession()
            val gate = CompletableDeferred<Unit>()
            activityHistoryRepository.saveActivityGate = gate
            val first = newSnapshotFile()
            val second = newSnapshotFile()

            finish(viewModel, first)
            finish(viewModel, second)
            assertEquals(listOf(first), filesInDir(), "the surplus file goes while the save is still running")
            gate.complete(Unit)
            testScheduler.runCurrent()
            finish(viewModel, newSnapshotFile())

            assertEquals(1, activityHistoryRepository.savedActivities.size)
            assertEquals(listOf(first), filesInDir())
            assertEquals(first, activityHistoryRepository.savedActivities.single().snapshotFilePath)
        }

    @Test
    fun `a repeated Finish with the saved file's own path does not delete it`() = runTest(testScheduler) {
        val viewModel = createFinishedSession()
        val file = newSnapshotFile()

        finish(viewModel, file)
        finish(viewModel, file)

        assertEquals(listOf(file), filesInDir())
    }

    @Test
    fun `a failed save keeps the file and the retry reuses it without a second file`() = runTest(testScheduler) {
        val viewModel = createFinishedSession()
        val file = newSnapshotFile()
        activityHistoryRepository.saveActivityFailure = IllegalStateException("disk full")

        finish(viewModel, file)

        assertEquals(listOf(file), filesInDir(), "kept while a retry can use it")
        assertEquals(file, viewModel.state.value.retainedSnapshotPath)

        activityHistoryRepository.saveActivityFailure = null
        finish(viewModel, viewModel.state.value.retainedSnapshotPath)

        assertEquals(listOf(file), filesInDir())
        assertEquals(file, activityHistoryRepository.savedActivities.single().snapshotFilePath)
        assertEquals(null, viewModel.state.value.retainedSnapshotPath)
    }

    @Test
    fun `a retry that brings a new file saves the kept one and deletes the new one`() = runTest(testScheduler) {
        val viewModel = createFinishedSession()
        val kept = newSnapshotFile()
        activityHistoryRepository.saveActivityFailure = IllegalStateException("disk full")
        finish(viewModel, kept)
        activityHistoryRepository.saveActivityFailure = null

        finish(viewModel, newSnapshotFile())

        assertEquals(listOf(kept), filesInDir())
        assertEquals(kept, activityHistoryRepository.savedActivities.single().snapshotFilePath)
    }

    @Test
    fun `a failed save then a new session without a retry deletes the file`() = runTest(testScheduler) {
        val viewModel = createFinishedSession()
        activityHistoryRepository.saveActivityFailure = IllegalStateException("disk full")
        finish(viewModel, newSnapshotFile())
        assertEquals(1, filesInDir().size)

        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        assertEquals(emptyList(), filesInDir())
        assertEquals(null, viewModel.state.value.retainedSnapshotPath)
        assertTrue(activityHistoryRepository.savedActivities.isEmpty())
    }

    @Test
    fun `a failed save then the ViewModel is cleared without a retry deletes the file`() = runTest(testScheduler) {
        val viewModel = createFinishedSession()
        activityHistoryRepository.saveActivityFailure = IllegalStateException("disk full")
        finish(viewModel, newSnapshotFile())
        assertEquals(1, filesInDir().size)

        viewModelStore.clear()

        assertEquals(emptyList(), filesInDir())
    }

    @Test
    fun `a Finish before the session is finished deletes its file`() = runTest(testScheduler) {
        val viewModel = createFinishedSession()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        finish(viewModel, newSnapshotFile())

        assertEquals(emptyList(), filesInDir())
    }

    @Test
    fun `the delete runs on the injected I O dispatcher, not on the calling one`() = runTest(testScheduler) {
        // Its own scheduler: nothing the main (test) scheduler runs executes this dispatcher's work.
        val ioScheduler = TestCoroutineScheduler()
        ioDispatcher = StandardTestDispatcher(ioScheduler)
        val viewModel = createFinishedSession()
        val file = newSnapshotFile()
        viewModel.onAction(TrackingAction.Start(START))
        testScheduler.runCurrent()

        finish(viewModel, file)

        assertEquals(listOf(file), filesInDir(), "the calling dispatcher did not delete the surplus file")
        ioScheduler.runCurrent()
        assertEquals(emptyList(), filesInDir())
    }

    @Test
    fun `a file retained after a failed save is still deleted when the ViewModel is cleared`() =
        runTest(testScheduler) {
            val ioScheduler = TestCoroutineScheduler()
            ioDispatcher = StandardTestDispatcher(ioScheduler)
            val viewModel = createFinishedSession()
            activityHistoryRepository.saveActivityFailure = IllegalStateException("disk full")
            finish(viewModel, newSnapshotFile())

            viewModelStore.clear()
            ioScheduler.runCurrent()

            assertEquals(emptyList(), filesInDir())
        }

    private companion object {
        val START = Coordinates(latitude = 52.000, longitude = 13.000)
    }
}
