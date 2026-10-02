//
//  TrackingSubject.swift
//  TrackingTests
//

import SharedKit
import TestSupport
import Tracking

/// A TrackingViewModel wired to a real TrackingSessionManager, CalorieCalculator and
/// SaveActivityUseCase, plus the fakes a test inspects.
@MainActor
struct TrackingSubject {
    let viewModel: TrackingViewModel
    let locationRepository: FakeLocationRepository
    let serviceLauncher: FakeTrackingServiceLauncher
    let userProfileRepository: FakeUserProfileRepository
    let activityHistoryRepository: FakeActivityHistoryRepository
    /// The ViewModel's and SaveActivityUseCase's clock (startedAt / endedAt).
    let clock: FakeClock

    /// - Parameters:
    ///   - scope: the TrackingSessionManager's scope; the caller cancels it when the test ends.
    ///   - updates: what each location collection (Start, Resume) emits.
    ///   - clockMillis: the fixed time `clock` reports until a test changes it.
    ///   - isProfileStorageFailing: whether the user profile repository throws (see FakeUserProfileRepository).
    init(
        scope: SwiftTestScope,
        updates: [any LocationUpdate],
        profile: UserProfile?,
        activityHistoryRepository: FakeActivityHistoryRepository,
        clockMillis: Int64,
        isProfileStorageFailing: Bool = false
    ) {
        let locationRepository = FakeLocationRepository(location: TrackingFixtures.startPoint, updates: updates)
        let serviceLauncher = FakeTrackingServiceLauncher()
        let userProfileRepository = FakeUserProfileRepository(profile: profile, isFailing: isProfileStorageFailing)
        let clock = FakeClock(nowMillis: clockMillis)
        let calorieCalculator = CalorieCalculator()
        let trackingSessionManager = TrackingSessionManager(
            locationRepository: locationRepository,
            updateTrackingStateUseCase: UpdateTrackingStateUseCase(),
            trackingServiceLauncher: serviceLauncher,
            // Swift can't see Kotlin default arguments; these repeat SpeedCalculator's defaults.
            speedCalculator: SpeedCalculator(windowSize: 5, acceptableAccuracyMeters: 20),
            // Its own clock, 10 s of elapsedRealtime per reading, so fixes produce elapsed time and
            // average speed.
            clock: FakeClock(nowMillis: 0, elapsedRealtimeMillis: 0, stepMillis: 10_000),
            logger: FakeLogger(),
            scope: scope
        )
        self.viewModel = TrackingViewModel(
            activityType: .running,
            plannedRoutePoints: TrackingFixtures.plannedRoutePoints,
            startPoint: TrackingFixtures.startPoint,
            trackingSessionManager: trackingSessionManager,
            userProfileRepository: userProfileRepository,
            calorieCalculator: calorieCalculator,
            saveActivityUseCase: SaveActivityUseCase(
                activityHistoryRepository: activityHistoryRepository,
                calorieCalculator: calorieCalculator,
                clock: clock
            ),
            clock: clock
        )
        self.locationRepository = locationRepository
        self.serviceLauncher = serviceLauncher
        self.userProfileRepository = userProfileRepository
        self.activityHistoryRepository = activityHistoryRepository
        self.clock = clock
    }
}
