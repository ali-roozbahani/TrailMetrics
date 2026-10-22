package dev.roozbahani.trailmetrics.shared.di

import dev.roozbahani.trailmetrics.data.local.dao.ActivityDao
import dev.roozbahani.trailmetrics.data.local.database.TrailMetricsDatabase
import dev.roozbahani.trailmetrics.data.local.entity.ActivityEntity
import dev.roozbahani.trailmetrics.domain.model.Coordinates
import dev.roozbahani.trailmetrics.domain.model.LocationUpdate
import dev.roozbahani.trailmetrics.domain.repository.LocationRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingServiceLauncher
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import org.koin.core.annotation.KoinInternalApi
import org.koin.core.context.stopKoin
import org.koin.core.module.Module
import org.koin.dsl.module
import kotlin.test.assertTrue

/**
 * Starts the graph [initKoin] builds, loads [overrides] over it and resolves every definition in the
 * registry. A binding that is missing or wrong in a real module makes the definition that needs it
 * fail with Koin's NoDefinitionFoundException (named in the message).
 *
 * [notResolved] lists the qualified names of definitions whose real binding needs a device and is
 * therefore not resolved; every consumer of one is overridden. koin-test's own `checkModules` is
 * deprecated and its `verify` only checks constructors by reflection on the JVM, so neither is used.
 */
@OptIn(KoinInternalApi::class)
internal fun checkKoinGraph(overrides: List<Module>, notResolved: Set<String>) {
    val koin = initKoin().koin
    try {
        koin.loadModules(overrides, allowOverride = true)
        val definitions = koin.instanceRegistry.instances.values.map { it.beanDefinition }.toSet()
        val resolved = definitions
            .filter { it.primaryType.qualifiedName !in notResolved + DEVICE_BOUND }
            .onEach { koin.get<Any>(it.primaryType, it.qualifier) }
        assertTrue(
            resolved.any { it.primaryType == TrackingSessionManager::class },
            "The graph has no TrackingSessionManager definition: the check resolved ${resolved.size} definitions"
        )
    } finally {
        stopKoin()
    }
}

// Room's generated database class cannot be faked and needs a device to open: its consumer, the DAO, is overridden.
private val DEVICE_BOUND = setOf(TrailMetricsDatabase::class.qualifiedName!!)

internal class FakeActivityDao : ActivityDao {
    override suspend fun insert(activity: ActivityEntity): Long = 0L
    override fun observeAll(): Flow<List<ActivityEntity>> = emptyFlow()
    override suspend fun getById(id: Long): ActivityEntity? = null
    override suspend fun delete(id: Long) = Unit
}

internal class FakeLocationRepository : LocationRepository {
    override suspend fun getCurrentLocation(): Result<Coordinates> = Result.success(Coordinates(0.0, 0.0))
    override fun observeLocationUpdates(): Flow<LocationUpdate> = emptyFlow()
}

internal class FakeTrackingServiceLauncher : TrackingServiceLauncher {
    override fun start() = Unit
    override fun stop() = Unit
}

/** The fakes of the pieces both platforms replace: the DAO, the location source and the tracking service. */
internal val commonFakesModule = module {
    single<ActivityDao> { FakeActivityDao() }
    single<LocationRepository> { FakeLocationRepository() }
    single<TrackingServiceLauncher> { FakeTrackingServiceLauncher() }
}
