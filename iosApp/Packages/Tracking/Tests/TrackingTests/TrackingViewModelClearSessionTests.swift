//
//  TrackingViewModelClearSessionTests.swift
//  TrackingTests
//
//  The stored session is cleared when it is saved as an activity or discarded, and only then;
//  a restored session is saved with the stored start time.
//

import SharedKit
import TestSupport
import Tracking
import XCTest

@MainActor
final class TrackingViewModelClearSessionTests: TrackingTestCase {

    func test_onFinishClicked_afterSave_clearsTheStoredSession() async {
        let store = FakeTrackingSessionStore()
        let subject = await makeFinishedSubject(sessionStore: store)

        var onSavedCallCount = 0
        subject.viewModel.onFinishClicked(snapshotFilePath: nil) { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount > 0 }

        XCTAssertEqual(store.clearCount, 1)
        XCTAssertNil(store.storedSession)
        XCTAssertEqual(subject.activityHistoryRepository.savedActivities.count, 1)
    }

    func test_onFinishClicked_afterFailedSave_doesNotClearTheStoredSession() async {
        let store = FakeTrackingSessionStore()
        let activityHistoryRepository = FakeActivityHistoryRepository()
        activityHistoryRepository.setFailing(true)
        let subject = await makeFinishedSubject(
            activityHistoryRepository: activityHistoryRepository,
            sessionStore: store
        )
        let recorder = EventRecorder(subject.viewModel.makeEventsStream())
        defer { recorder.stop() }

        subject.viewModel.onFinishClicked(snapshotFilePath: nil) {}
        await waitUntil { !recorder.events.isEmpty }

        XCTAssertEqual(store.clearCount, 0)
        XCTAssertNotNil(store.storedSession)
    }

    func test_onFinishClicked_whenTheClearFails_stillClosesTheScreenOnce() async {
        let store = FakeTrackingSessionStore()
        let subject = await makeFinishedSubject(sessionStore: store)
        store.setClearFailing(true)

        var onSavedCallCount = 0
        subject.viewModel.onFinishClicked(snapshotFilePath: nil) { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount > 0 }

        XCTAssertEqual(onSavedCallCount, 1, "The manager logs a failed clear; the save is not reported as failed")
        XCTAssertEqual(store.clearCount, 1)
    }

    func test_onDiscardClicked_stopsAndClearsTheStoredSession() async {
        let store = FakeTrackingSessionStore()
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates, sessionStore: store)
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }

        viewModel.onDiscardClicked()
        await waitUntil { store.clearCount == 1 }

        XCTAssertTrue(viewModel.isDiscarding)
        XCTAssertFalse(viewModel.canFinish, "The Finish card is not shown while the screen leaves")
        XCTAssertEqual(subject.serviceLauncher.stopCount, 1)
        XCTAssertNil(store.storedSession)
    }

    func test_onStopClicked_atTheRouteEnd_keepsTheStoredSessionForFinish() async {
        let store = FakeTrackingSessionStore()
        let subject = await makeFinishedSubject(sessionStore: store)

        XCTAssertEqual(store.clearCount, 0)
        XCTAssertTrue(subject.viewModel.canFinish)
    }

    func test_onFinishClicked_forARestoredFinishedSession_savesWithTheStoredStartTimeAndClears() async {
        let storedStart: Int64 = 1_699_999_000_000
        let finished = TrackingStateFinished(metrics: TrackingFixtures.metrics(path: TrackingFixtures.movingPath))
        let store = FakeTrackingSessionStore(
            stored: TrackingFixtures.storedSession(finished, activityType: .running, startedAtEpochMillis: storedStart)
        )
        let subject = makeSubject(profile: UserProfile(weightKg: Self.weightKg), sessionStore: store)
        let viewModel = subject.viewModel

        do {
            _ = try await subject.trackingSessionManager.restore()
        } catch {
            return XCTFail("restore() must not fail: \(error)")
        }
        await waitUntil { viewModel.canFinish && viewModel.calories == nil }
        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: nil) { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount > 0 }

        XCTAssertEqual(subject.activityHistoryRepository.savedActivities.first?.startedAtEpochMillis, storedStart)
        XCTAssertEqual(store.clearCount, 1)
    }
}
