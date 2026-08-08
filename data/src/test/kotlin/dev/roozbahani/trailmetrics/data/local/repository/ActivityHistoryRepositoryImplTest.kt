package dev.roozbahani.trailmetrics.data.local.repository

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase
import dev.roozbahani.trailmetrics.domain.model.ActivityRecord
import dev.roozbahani.trailmetrics.domain.model.ActivityType
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ActivityHistoryRepositoryImplTest {

    private lateinit var database: TrailMetricsDatabase
    private lateinit var repository: ActivityHistoryRepositoryImpl

    private val point1 = Coordinates(51.336, 12.388)
    private val point2 = Coordinates(51.337, 12.389)

    @OptIn(ExperimentalCoroutinesApi::class)
    @Before
    fun setup() {
        database = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            TrailMetricsDatabase::class.java
        ).build()
        repository = ActivityHistoryRepositoryImpl(
            activityDao = database.activityDao(),
            ioDispatcher = UnconfinedTestDispatcher()
        )
    }

    @After
    fun teardown() {
        database.close()
    }

    @Test
    fun `observeActivities returns empty list when no activities are saved`() = runTest {
        val result = repository.observeActivities().first()
        assertThat(result).isEmpty()
    }

    @Test
    fun `saveActivity returns a valid generated id`() = runTest {
        val newRecord = sampleActivity()
        val generatedId = repository.saveActivity(newRecord)
        assertThat(generatedId).isNotEqualTo(0)
    }

    @Test
    fun `saveActivity then observeActivities returns the saved activity`() = runTest {
        var newRecord = sampleActivity()
        val generatedId = repository.saveActivity(newRecord)
        newRecord = newRecord.copy(id = generatedId)

        val observedActivities = repository.observeActivities().first()
        assertThat(observedActivities).containsExactly(newRecord)
    }

    @Test
    fun `getActivity returns the correct activity for an existing id`() = runTest {
        var newRecord = sampleActivity()
        val generatedId = repository.saveActivity(newRecord)
        newRecord = newRecord.copy(id = generatedId)

        val activity = repository.getActivity(generatedId)
        assertThat(activity).isEqualTo(newRecord)
    }

    @Test
    fun `getActivity returns null for a non-existing id`() = runTest {
        repository.saveActivity(sampleActivity())

        val activity = repository.getActivity(id = 12L) // only id = 1 exists
        assertThat(activity).isNull()
    }

    @Test
    fun `deleteActivity removes the activity from the database`() = runTest {
        val newRecord = sampleActivity()
        val generatedId = repository.saveActivity(newRecord)

        assertThat(repository.getActivity(generatedId)).isNotNull() // assert new activity exists

        repository.deleteActivity(generatedId) // remove it from database

        assertThat(repository.getActivity(generatedId)).isNull() // assert new activity does not exist anymore
    }

    @Test
    fun `observeActivities emits activities ordered by most recent first`() = runTest {
        var activity1 = sampleActivity(startedAtEpochMillis = 1_000L)
        val genId1 = repository.saveActivity(activity1)
        activity1 = activity1.copy(id = genId1)

        var activity2 = sampleActivity(startedAtEpochMillis = 2_000L)
        val genId2 = repository.saveActivity(activity2)
        activity2 = activity2.copy(id = genId2)

        var activity3 = sampleActivity(startedAtEpochMillis = 3_000L)
        val genId3 = repository.saveActivity(activity3)
        activity3 = activity3.copy(id = genId3)

        val observedActivities = repository.observeActivities().first()
        assertThat(observedActivities).containsExactly(
            activity3,
            activity2,
            activity1
        ) // ORDERED DESC
    }

    private fun sampleActivity(
        id: Long = 0,
        activityType: ActivityType = ActivityType.Walking,
        startedAtEpochMillis: Long = 1_000L,
        endedAtEpochMillis: Long = 2_000L,
        distanceMeters: Double = 100.0,
        durationMillis: Long = 1_000L,
        averageSpeedMetersPerSecond: Float = 15f,
        calories: Double = 30.0,
        plannedRoutePoints: List<Coordinates> = listOf(point1, point2),
        actualPath: List<Coordinates> = listOf(point1, point2),
        snapshotFilePath: String? = null
    ) = ActivityRecord(
        id = id,
        activityType = activityType,
        startedAtEpochMillis = startedAtEpochMillis,
        endedAtEpochMillis = endedAtEpochMillis,
        distanceMeters = distanceMeters,
        durationMillis = durationMillis,
        averageSpeedMetersPerSecond = averageSpeedMetersPerSecond,
        calories = calories,
        plannedRoutePoints = plannedRoutePoints,
        actualPath = actualPath,
        snapshotFilePath = snapshotFilePath
    )
}
