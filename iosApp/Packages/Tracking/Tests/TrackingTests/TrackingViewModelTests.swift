//
//  TrackingViewModelTests.swift
//  TrackingTests
//
//  Characterizes today's intent-method TrackingViewModel (iOS isn't part of the MVI
//  migration). It drives a real TrackingSessionManager built from fakes and a
//  SwiftTestScope, the real CalorieCalculator, and a real SaveActivityUseCase around
//  FakeActivityHistoryRepository.
//

import SharedKit
import TestSupport
import Tracking
import XCTest

@MainActor
final class TrackingViewModelTests: XCTestCase {

    private static let weightKg = 70.0
    private static let startedAtMillis: Int64 = 1_700_000_000_000
    private static let finishedAtMillis: Int64 = 1_700_000_600_000

    private var scopes: [SwiftTestScope] = []

    override func tearDown() async throws {
        scopes.forEach { $0.cancel() }
        scopes = []
        try await super.tearDown()
    }

    // MARK: - State transitions

    func test_init_isIdleAndOnlyStartIsAvailable() {
        let viewModel = makeSubject().viewModel

        XCTAssertTrue(viewModel.trackingState is TrackingStateIdle)
        XCTAssertTrue(viewModel.canStart)
        XCTAssertFalse(viewModel.canPause)
        XCTAssertFalse(viewModel.canResume)
        XCTAssertFalse(viewModel.canStop)
        XCTAssertTrue(viewModel.currentPath.isEmpty)
        XCTAssertNil(viewModel.currentMetrics)
        XCTAssertNil(viewModel.calories)
    }

    func test_onStartClicked_transitionsToTrackingFromStartPointAndStartsService() async {
        let subject = makeSubject()
        let viewModel = subject.viewModel

        viewModel.onStartClicked()

        await waitUntil { viewModel.trackingState is TrackingStateTracking }
        XCTAssertEqual(viewModel.currentPath, [TrackingFixtures.startPoint])
        XCTAssertFalse(viewModel.canStart)
        XCTAssertTrue(viewModel.canPause)
        XCTAssertFalse(viewModel.canResume)
        XCTAssertTrue(viewModel.canStop)
        XCTAssertEqual(subject.serviceLauncher.startCount, 1)
        XCTAssertEqual(subject.locationRepository.observeCallCount, 1)
    }

    func test_onStartClicked_appendsLocationUpdatesToPathAndMetrics() async {
        let viewModel = makeSubject(updates: TrackingFixtures.movingUpdates).viewModel

        viewModel.onStartClicked()

        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }
        XCTAssertEqual(viewModel.currentPath, TrackingFixtures.movingPath)
        let metrics = viewModel.currentMetrics
        XCTAssertEqual(metrics?.path, TrackingFixtures.movingPath)
        XCTAssertGreaterThan(metrics?.distanceMeters ?? 0, 0)
        XCTAssertGreaterThan(metrics?.elapsedMillis ?? 0, 0)
    }

    func test_onPauseClicked_transitionsToPausedKeepingMetrics() async {
        let viewModel = makeSubject(updates: TrackingFixtures.movingUpdates).viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }

        viewModel.onPauseClicked()

        await waitUntil { viewModel.trackingState is TrackingStatePaused }
        XCTAssertEqual(viewModel.currentPath, TrackingFixtures.movingPath)
        XCTAssertFalse(viewModel.canStart)
        XCTAssertFalse(viewModel.canPause)
        XCTAssertTrue(viewModel.canResume)
        XCTAssertTrue(viewModel.canStop)
    }

    func test_onResumeClicked_transitionsBackToTrackingAndObservesLocationAgain() async {
        let subject = makeSubject()
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.trackingState is TrackingStateTracking }
        viewModel.onPauseClicked()
        await waitUntil { viewModel.trackingState is TrackingStatePaused }

        viewModel.onResumeClicked()

        await waitUntil { viewModel.trackingState is TrackingStateTracking }
        XCTAssertTrue(viewModel.canPause)
        XCTAssertFalse(viewModel.canResume)
        XCTAssertEqual(subject.locationRepository.observeCallCount, 2)
    }

    func test_onStopClicked_fromTracking_isFinishedSynchronouslyAndStopsService() async {
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates)
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }

        viewModel.onStopClicked()

        // No waiting: onStopClicked() reads the manager's state back itself.
        guard let finished = viewModel.trackingState as? TrackingStateFinished else {
            return XCTFail("Expected Finished, got \(viewModel.trackingState)")
        }
        XCTAssertEqual(finished.metrics.path, TrackingFixtures.movingPath)
        XCTAssertTrue(viewModel.canStart)
        XCTAssertFalse(viewModel.canPause)
        XCTAssertFalse(viewModel.canResume)
        XCTAssertFalse(viewModel.canStop)
        XCTAssertTrue(viewModel.currentPath.isEmpty, "currentPath only covers Tracking and Paused")
        XCTAssertNil(viewModel.currentMetrics, "currentMetrics only covers Tracking and Paused")
        XCTAssertEqual(subject.serviceLauncher.stopCount, 1)
    }

    func test_onStopClicked_fromPaused_isFinished() async {
        let viewModel = makeSubject().viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.trackingState is TrackingStateTracking }
        viewModel.onPauseClicked()
        await waitUntil { viewModel.trackingState is TrackingStatePaused }

        viewModel.onStopClicked()

        XCTAssertTrue(viewModel.trackingState is TrackingStateFinished)
    }

    // MARK: - Calories

    func test_calories_withProfileAndAverageSpeed_areComputedFromCurrentMetrics() async {
        let viewModel = makeSubject(
            updates: TrackingFixtures.movingUpdates,
            profile: UserProfile(weightKg: Self.weightKg)
        ).viewModel

        viewModel.onStartClicked()

        await waitUntil {
            viewModel.currentPath.count == TrackingFixtures.movingPath.count && viewModel.calories != nil
        }
        XCTAssertEqual(viewModel.calories, expectedCalories(for: viewModel))
    }

    func test_calories_withoutProfile_areNil() async {
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates, profile: nil)
        let viewModel = subject.viewModel

        viewModel.onStartClicked()

        await waitUntil {
            viewModel.currentPath.count == TrackingFixtures.movingPath.count
                && subject.userProfileRepository.getUserProfileCallCount == 1
        }
        XCTAssertNotNil(viewModel.currentMetrics?.averageSpeedMetersPerSecond)
        XCTAssertNil(viewModel.calories)
    }

    func test_calories_withoutAverageSpeed_areNil() async {
        // No location updates: elapsed time stays 0, so there's no average speed.
        let subject = makeSubject(profile: UserProfile(weightKg: Self.weightKg))
        let viewModel = subject.viewModel

        viewModel.onStartClicked()

        await waitUntil {
            viewModel.trackingState is TrackingStateTracking
                && subject.userProfileRepository.getUserProfileCallCount == 1
        }
        XCTAssertNil(viewModel.currentMetrics?.averageSpeedMetersPerSecond)
        XCTAssertNil(viewModel.calories)
    }

    func test_calories_areRecomputedWhenMetricsChange() async {
        let viewModel = makeSubject(
            updates: TrackingFixtures.movingUpdates,
            profile: UserProfile(weightKg: Self.weightKg)
        ).viewModel
        viewModel.onStartClicked()
        await waitUntil {
            viewModel.currentPath.count == TrackingFixtures.movingPath.count && viewModel.calories != nil
        }
        let caloriesBeforePause = viewModel.calories
        viewModel.onPauseClicked()
        await waitUntil { viewModel.trackingState is TrackingStatePaused }
        XCTAssertEqual(viewModel.calories, caloriesBeforePause, "Paused keeps the same metrics")

        // Resuming collects the cold fake flow again, so both fixes are appended a second time.
        viewModel.onResumeClicked()

        let resumedPathCount = TrackingFixtures.movingPath.count + TrackingFixtures.movingUpdates.count
        await waitUntil { viewModel.currentPath.count == resumedPathCount }
        XCTAssertEqual(viewModel.calories, expectedCalories(for: viewModel))
        XCTAssertNotEqual(viewModel.calories, caloriesBeforePause)
    }

    func test_calories_afterStop_areNil() async {
        let viewModel = makeSubject(
            updates: TrackingFixtures.movingUpdates,
            profile: UserProfile(weightKg: Self.weightKg)
        ).viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.calories != nil }

        viewModel.onStopClicked()

        // Today's behavior: recomputeCalories() reads currentMetrics, which excludes Finished.
        XCTAssertNil(viewModel.calories)
    }

    // MARK: - Finish

    func test_onFinishClicked_whenFinishedWithProfile_savesActivityAndCallsOnSavedOnce() async {
        let subject = await makeFinishedSubject()
        let viewModel = subject.viewModel
        guard let finalMetrics = (viewModel.trackingState as? TrackingStateFinished)?.metrics else {
            return XCTFail("Expected Finished, got \(viewModel.trackingState)")
        }
        // startedAtEpochMillis must be the clock reading at Start, not at Finish.
        subject.clock.setNowMillis(Self.finishedAtMillis)

        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "/tmp/snapshot.png") { onSavedCallCount += 1 }

        await waitUntil { onSavedCallCount > 0 }
        await Task.yield()
        XCTAssertEqual(onSavedCallCount, 1)
        XCTAssertEqual(subject.activityHistoryRepository.savedActivities.count, 1)
        guard let saved = subject.activityHistoryRepository.savedActivities.first else { return }
        XCTAssertEqual(saved.activityType, .running)
        XCTAssertEqual(saved.plannedRoutePoints, TrackingFixtures.plannedRoutePoints)
        XCTAssertEqual(saved.actualPath, TrackingFixtures.movingPath)
        XCTAssertEqual(saved.distanceMeters, finalMetrics.distanceMeters)
        XCTAssertEqual(saved.durationMillis, finalMetrics.elapsedMillis)
        XCTAssertEqual(saved.startedAtEpochMillis, Self.startedAtMillis)
        XCTAssertEqual(saved.endedAtEpochMillis, Self.finishedAtMillis)
        XCTAssertEqual(saved.snapshotFilePath, "/tmp/snapshot.png")
        XCTAssertEqual(
            saved.calories?.doubleValue,
            expectedCalories(metrics: finalMetrics, activityType: .running)
        )
    }

    func test_onFinishClicked_whenNotFinished_savesNothing() async {
        let subject = makeSubject(
            updates: TrackingFixtures.movingUpdates,
            profile: UserProfile(weightKg: Self.weightKg)
        )
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.calories != nil }

        var ignoredOnSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "ignored") { ignoredOnSavedCallCount += 1 }

        // Barrier: a later valid finish on the same ViewModel and repository. If the call
        // above had started a save, it would have been queued first.
        viewModel.onStopClicked()
        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "saved") { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount > 0 }
        await Task.yield()

        XCTAssertEqual(ignoredOnSavedCallCount, 0)
        XCTAssertEqual(subject.activityHistoryRepository.savedActivities.map(\.snapshotFilePath), ["saved"])
    }

    func test_onFinishClicked_withoutProfile_savesNothing() async {
        let activityHistoryRepository = FakeActivityHistoryRepository()
        let subject = makeSubject(
            updates: TrackingFixtures.movingUpdates,
            profile: nil,
            activityHistoryRepository: activityHistoryRepository
        )
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil {
            viewModel.currentPath.count == TrackingFixtures.movingPath.count
                && subject.userProfileRepository.getUserProfileCallCount == 1
        }
        viewModel.onStopClicked()

        var ignoredOnSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "ignored") { ignoredOnSavedCallCount += 1 }

        // Barrier: a valid finish on a second ViewModel sharing the same repository.
        let barrier = await makeFinishedSubject(activityHistoryRepository: activityHistoryRepository)
        var onSavedCallCount = 0
        barrier.viewModel.onFinishClicked(snapshotFilePath: "saved") { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount > 0 }
        await Task.yield()

        XCTAssertEqual(ignoredOnSavedCallCount, 0)
        XCTAssertEqual(activityHistoryRepository.savedActivities.map(\.snapshotFilePath), ["saved"])
    }

    // MARK: - Profile load

    // The profile is loaded only once, from init, so there is no later successful load to
    // assert; without a profile, calories stay nil and Finish saves nothing (see above).
    func test_init_profileLoadFails_emitsGeneralErrorAndLeavesProfileUnset() async {
        let subject = makeSubject(
            updates: TrackingFixtures.movingUpdates,
            profile: UserProfile(weightKg: Self.weightKg),
            isProfileStorageFailing: true
        )
        let viewModel = subject.viewModel
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        guard case .showError(let error) = recorder.events.first else {
            return XCTFail("Expected showError, got \(recorder.events)")
        }
        XCTAssertTrue(error is RouteUiErrorGeneral)

        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }
        XCTAssertEqual(subject.userProfileRepository.getUserProfileCallCount, 1)
        XCTAssertNil(viewModel.calories, "no profile was loaded, so no calories")
    }

    // MARK: - Helpers

    private func makeSubject(
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
    private func makeFinishedSubject(
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

    private func expectedCalories(for viewModel: TrackingViewModel) -> Double? {
        viewModel.currentMetrics.flatMap { expectedCalories(metrics: $0, activityType: viewModel.activityType) }
    }

    private func expectedCalories(metrics: TrackingMetrics, activityType: ActivityType) -> Double? {
        guard let averageSpeed = metrics.averageSpeedMetersPerSecond?.floatValue else { return nil }
        return CalorieCalculator().calculate(
            activityType: activityType,
            averageSpeedMetersPerSecond: averageSpeed,
            weightKg: Self.weightKg,
            durationMillis: metrics.elapsedMillis
        )
    }
}
