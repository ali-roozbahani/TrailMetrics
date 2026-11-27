//
//  TrackingViewModelDiscardFinishedTests.swift
//  TrackingTests
//
//  Discard of a Finished session: offered for Finished only (`domain`'s `canDiscard`), it deletes the session
//  without saving it, and the screen stays, Idle with Start offered.
//

import SharedKit
import TestSupport
import Tracking
import XCTest

@MainActor
final class TrackingViewModelDiscardFinishedTests: TrackingTestCase {

    /// A session with a loaded profile and both moving fixes, finished by the manager as at the route's end: the
    /// ViewModel keeps observing, unlike after `onStopClicked()` (which only a leaving screen calls).
    private func makeSessionFinishedByTheManager(sessionStore: FakeTrackingSessionStore) async -> TrackingSubject {
        let subject = makeSubject(
            updates: TrackingFixtures.movingUpdates,
            profile: UserProfile(weightKg: Self.weightKg),
            sessionStore: sessionStore
        )
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil {
            viewModel.currentPath.count == TrackingFixtures.movingPath.count && viewModel.calories != nil
        }
        subject.trackingSessionManager.stop()
        await waitUntil { viewModel.canFinish }
        return subject
    }

    func test_canDiscardFinished_isOfferedForAFinishedSessionOnly() async {
        let viewModel = makeSubject(updates: TrackingFixtures.movingUpdates).viewModel
        XCTAssertFalse(viewModel.canDiscardFinished, "idle")

        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }
        XCTAssertFalse(viewModel.canDiscardFinished, "tracking")

        viewModel.onPauseClicked()
        await waitUntil { viewModel.trackingState is TrackingStatePaused }
        XCTAssertFalse(viewModel.canDiscardFinished, "paused")

        viewModel.onStopClicked()
        XCTAssertTrue(viewModel.trackingState is TrackingStateFinished)
        XCTAssertTrue(viewModel.canDiscardFinished, "finished")
        XCTAssertTrue(viewModel.canFinish, "finished")
    }

    func test_onDiscardFinishedClicked_leavesIdleClearsTheStoredSessionAndOffersStart() async {
        let store = FakeTrackingSessionStore()
        let subject = await makeSessionFinishedByTheManager(sessionStore: store)
        let viewModel = subject.viewModel
        XCTAssertNotNil(store.storedSession)
        XCTAssertFalse(viewModel.canStart)

        viewModel.onDiscardFinishedClicked()
        await waitUntil { viewModel.trackingState is TrackingStateIdle }

        XCTAssertEqual(store.clearCount, 1)
        XCTAssertNil(store.storedSession)
        XCTAssertTrue(subject.activityHistoryRepository.savedActivities.isEmpty)
        XCTAssertFalse(viewModel.isDiscarding, "The screen stays")
        XCTAssertTrue(viewModel.canStart)
        XCTAssertFalse(viewModel.canFinish)
        XCTAssertFalse(viewModel.canDiscardFinished)
    }

    func test_onDiscardFinishedClicked_forARestoredFinishedSession_leavesIdleAndANewSessionStarts() async {
        let finished = TrackingStateFinished(metrics: TrackingFixtures.metrics(path: TrackingFixtures.movingPath))
        let store = FakeTrackingSessionStore(stored: TrackingFixtures.storedSession(finished))
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates, sessionStore: store)
        let viewModel = subject.viewModel
        do {
            _ = try await subject.trackingSessionManager.restore()
        } catch {
            return XCTFail("restore() must not fail: \(error)")
        }
        await waitUntil { viewModel.canDiscardFinished }

        viewModel.onDiscardFinishedClicked()
        await waitUntil { viewModel.canStart }
        XCTAssertNil(store.storedSession)

        viewModel.onStartClicked()
        await waitUntil { viewModel.trackingState is TrackingStateTracking }
        XCTAssertTrue(viewModel.canPause)
    }

    func test_onDiscardFinishedClicked_twice_discardsOnce() async {
        let store = FakeTrackingSessionStore()
        let subject = await makeSessionFinishedByTheManager(sessionStore: store)
        let viewModel = subject.viewModel

        viewModel.onDiscardFinishedClicked()
        XCTAssertFalse(viewModel.canDiscardFinished, "Not offered again while the discard runs")
        viewModel.onDiscardFinishedClicked()
        await waitUntil { viewModel.canStart }

        XCTAssertEqual(store.clearCount, 1)
    }

    func test_onDiscardFinishedClicked_whileTracking_doesNothing() async {
        let store = FakeTrackingSessionStore()
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates, sessionStore: store)
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }

        viewModel.onDiscardFinishedClicked()

        XCTAssertTrue(viewModel.trackingState is TrackingStateTracking)
        XCTAssertEqual(store.clearCount, 0)
        XCTAssertEqual(subject.serviceLauncher.stopCount, 0)
    }

    func test_onDiscardFinishedClicked_whileAFinishSaves_doesNothingAndTheSaveClearsOnce() async {
        let store = FakeTrackingSessionStore()
        let subject = await makeSessionFinishedByTheManager(sessionStore: store)
        let viewModel = subject.viewModel

        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: nil) { onSavedCallCount += 1 }
        XCTAssertFalse(viewModel.canDiscardFinished, "Not offered while the save runs")
        viewModel.onDiscardFinishedClicked()
        await waitUntil { onSavedCallCount > 0 }

        XCTAssertEqual(subject.activityHistoryRepository.savedActivities.count, 1)
        XCTAssertEqual(store.clearCount, 1)
    }

    func test_canDiscardFinished_isFalseWhileTheScreenLeavesThroughStop() async {
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates)
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }

        viewModel.onDiscardClicked()

        XCTAssertFalse(viewModel.canDiscardFinished)
    }
}
