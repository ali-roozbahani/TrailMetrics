package dev.roozbahani.trailmetrics.shared.di

import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.tracking.TrackingSessionManager
import dev.roozbahani.trailmetrics.domain.usecase.GenerateClosedRouteUseCase
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import dev.roozbahani.trailmetrics.domain.usecase.SaveActivityUseCase
import dev.roozbahani.trailmetrics.domain.util.CalorieCalculator
import dev.roozbahani.trailmetrics.domain.util.Clock
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

class KoinHelper : KoinComponent {
    private val activityHistoryRepository: ActivityHistoryRepository by inject()
    private val currentLocationUseCase: GetCurrentLocationUseCase by inject()
    private val closedRouteUseCase: GenerateClosedRouteUseCase by inject()
    private val userProfileRepositoryDep: UserProfileRepository by inject()
    private val trackingSessionManagerDep: TrackingSessionManager by inject()
    private val saveActivityUseCaseDep: SaveActivityUseCase by inject()
    private val calorieCalculatorDep: CalorieCalculator by inject()
    private val clockDep: Clock by inject()

    fun getActivityHistoryRepository(): ActivityHistoryRepository = activityHistoryRepository
    fun getCurrentLocationUseCase(): GetCurrentLocationUseCase = currentLocationUseCase
    fun generateClosedRouteUseCase(): GenerateClosedRouteUseCase = closedRouteUseCase
    fun userProfileRepository(): UserProfileRepository = userProfileRepositoryDep
    fun trackingSessionManager(): TrackingSessionManager = trackingSessionManagerDep
    fun saveActivityUseCase(): SaveActivityUseCase = saveActivityUseCaseDep
    fun calorieCalculator(): CalorieCalculator = calorieCalculatorDep
    fun clock(): Clock = clockDep
}
