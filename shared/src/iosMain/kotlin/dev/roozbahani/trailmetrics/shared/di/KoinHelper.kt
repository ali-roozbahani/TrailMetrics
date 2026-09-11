package dev.roozbahani.trailmetrics.shared.di

import dev.roozbahani.trailmetrics.domain.repository.ActivityHistoryRepository
import dev.roozbahani.trailmetrics.domain.repository.UserProfileRepository
import dev.roozbahani.trailmetrics.domain.usecase.GenerateClosedRouteUseCase
import dev.roozbahani.trailmetrics.domain.usecase.GetCurrentLocationUseCase
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

class KoinHelper : KoinComponent {
    private val activityHistoryRepository: ActivityHistoryRepository by inject()
    private val currentLocationUseCase: GetCurrentLocationUseCase by inject()
    private val closedRouteUseCase: GenerateClosedRouteUseCase by inject()
    private val userProfileRepositoryDep: UserProfileRepository by inject()

    fun getActivityHistoryRepository(): ActivityHistoryRepository = activityHistoryRepository
    fun getCurrentLocationUseCase(): GetCurrentLocationUseCase = currentLocationUseCase
    fun generateClosedRouteUseCase(): GenerateClosedRouteUseCase = closedRouteUseCase
    fun userProfileRepository(): UserProfileRepository = userProfileRepositoryDep
}
