//
//  TrackingSubject.swift
//  TrackingTests
//

import SharedKit
import TestSupport
@testable import Tracking

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
    let sessionStore: FakeTrackingSessionStore
    let trackingSessionManager: TrackingSessionManager
    /// The ViewModel's source of `isRestoring`; false unless the subject is made with `isRestoring: true`.
    let savedSessionOffer: SavedSessionOfferModel

    /// - Parameters:
    ///   - scope: the TrackingSessionManager's scope; the caller cancels it when the test ends.
    ///   - updates: what each location collection (Start, Resume) emits.
    ///   - clockMillis: the fixed time `clock` reports until a test changes it.
    ///   - sessionStore: the store behind the TrackingSessionManager.
    ///   - userProfileRepository: replaces the one built from `profile` and `isProfileStorageFailing`.
    ///   - isRestoring: whether the stored session is still being read (the model starts restoring).
    ///   - isProfileStorageFailing: whether the user profile repository throws (see FakeUserProfileRepository).
    init(
        scope: SwiftTestScope,
        updates: [any LocationUpdate],
        profile: UserProfile?,
        activityHistoryRepository: FakeActivityHistoryRepository,
        clockMillis: Int64,
        isProfileStorageFailing: Bool = false,
        sessionStore: FakeTrackingSessionStore = FakeTrackingSessionStore(),
        userProfileRepository: FakeUserProfileRepository? = nil,
        isRestoring: Bool = false
    ) {
        let locationRepository = FakeLocationRepository(location: TrackingFixtures.startPoint, updates: updates)
        let serviceLauncher = FakeTrackingServiceLauncher()
        let userProfileRepository = userProfileRepository
            ?? FakeUserProfileRepository(profile: profile, isFailing: isProfileStorageFailing)
        let clock = FakeClock(nowMillis: clockMillis)
        let calorieCalculator = CalorieCalculator()
        let trackingSessionManager = TrackingSessionManager(
            locationRepository: locationRepository,
            updateTrackingStateUseCase: UpdateTrackingStateUseCase(),
            trackingServiceLauncher: serviceLauncher,
            // Swift can't see Kotlin default arguments; these repeat SpeedCalculator's defaults.
            speedCalculator: SpeedCalculator(windowSize: 5, acceptableAccuracyMeters: 20),
            // Its own clock, 10 s of elapsedRealtime per reading, so fixes produce elapsed time and
            // average speed. Its wall clock reads `clockMillis` (the session's start time).
            clock: FakeClock(nowMillis: clockMillis, elapsedRealtimeMillis: 0, stepMillis: 10_000),
            logger: FakeLogger(),
            trackingSessionStore: sessionStore,
            scope: scope
        )
        let savedSessionOffer = SavedSessionOfferModel(
            trackingSessionManager: trackingSessionManager,
            endOrphanedLiveActivities: {},
            isRestoring: isRestoring
        )
        self.viewModel = TrackingViewModel(
            activityType: .running,
            plannedRoutePoints: TrackingFixtures.plannedRoutePoints,
            startPoint: TrackingFixtures.startPoint,
            storedSessionReadState: savedSessionOffer,
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
        self.sessionStore = sessionStore
        self.trackingSessionManager = trackingSessionManager
        self.savedSessionOffer = savedSessionOffer
    }
}
