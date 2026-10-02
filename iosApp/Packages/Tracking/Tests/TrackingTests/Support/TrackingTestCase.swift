//
//  TrackingTestCase.swift
//  TrackingTests
//

import SharedKit
import TestSupport
import Tracking
import XCTest

/// Base class of the TrackingViewModel test classes: builds subjects and cancels their
/// TrackingSessionManager scopes when each test ends.
@MainActor
class TrackingTestCase: XCTestCase {

    static let weightKg = 70.0
    static let startedAtMillis: Int64 = 1_700_000_000_000
    static let finishedAtMillis: Int64 = 1_700_000_600_000

    private var scopes: [SwiftTestScope] = []

    override func tearDown() async throws {
        scopes.forEach { $0.cancel() }
        scopes = []
        try await super.tearDown()
    }

    func makeSubject(
        updates: [any LocationUpdate] = [],
        profile: UserProfile? = nil,
        activityHistoryRepository: FakeActivityHistoryRepository = FakeActivityHistoryRepository(),
        isProfileStorageFailing: Bool = false
    ) -> TrackingSubject {
        let scope = SwiftTestScope()
        scopes.append(scope)
        return TrackingSubject(
            scope: scope,
            updates: updates,
            profile: profile,
            activityHistoryRepository: activityHistoryRepository,
            clockMillis: Self.startedAtMillis,
            isProfileStorageFailing: isProfileStorageFailing
        )
    }

    /// A session with a loaded profile, both moving fixes recorded, then stopped.
    func makeFinishedSubject(
        activityHistoryRepository: FakeActivityHistoryRepository = FakeActivityHistoryRepository()
    ) async -> TrackingSubject {
        let subject = makeSubject(
            updates: TrackingFixtures.movingUpdates,
            profile: UserProfile(weightKg: Self.weightKg),
            activityHistoryRepository: activityHistoryRepository
        )
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        // calories != nil means the profile has been loaded into the ViewModel.
        await waitUntil {
            viewModel.currentPath.count == TrackingFixtures.movingPath.count && viewModel.calories != nil
        }
        viewModel.onStopClicked()
        return subject
    }

    func expectedCalories(for viewModel: TrackingViewModel) -> Double? {
        viewModel.currentMetrics.flatMap { expectedCalories(metrics: $0, activityType: viewModel.activityType) }
    }

    func expectedCalories(metrics: TrackingMetrics, activityType: ActivityType) -> Double? {
        guard let averageSpeed = metrics.averageSpeedMetersPerSecond?.floatValue else { return nil }
        return CalorieCalculator().calculate(
            activityType: activityType,
            averageSpeedMetersPerSecond: averageSpeed,
            weightKg: Self.weightKg,
            durationMillis: metrics.elapsedMillis
        )
    }
}
