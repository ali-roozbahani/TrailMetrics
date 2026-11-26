//
//  TrackingViewModelSaveFailureTests.swift
//  TrackingTests
//
//  A failing save of the in-progress session is shown once per session (`sessionNotSaved`), not on every
//  failed write, and tracking goes on (owner decision of 2026-11-25).
//

import SharedKit
import TestSupport
import Tracking
import XCTest

@MainActor
final class TrackingViewModelSaveFailureTests: TrackingTestCase {

    func test_failingSaves_emitSessionNotSavedOnce_andTrackingGoesOn() async {
        let store = FakeTrackingSessionStore()
        store.setSaveFailing(true)
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates, sessionStore: store)
        let viewModel = subject.viewModel
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }
        await waitUntil { !recorder.events.isEmpty }
        // Every fix was a failed save; a pause is one more.
        viewModel.onPauseClicked()
        await waitUntil { viewModel.canResume }

        XCTAssertEqual(recorder.events.filter(\.isSessionNotSaved).count, 1, "got \(recorder.events)")
        let warning = subject.trackingSessionManager.unsavedSessionWarning
        XCTAssertTrue(warning.isRaised.value.boolValue, "queued, not yet shown: still raised")
        XCTAssertNil(store.storedSession)

        viewModel.onSessionNotSavedShown()

        XCTAssertFalse(warning.isRaised.value.boolValue, "shown, so cleared")
    }

    /// Like TrackingView's `.task` cancelled before it showed the message (or the event evicted from the pending
    /// list): while the warning is raised, the next stream gets it again.
    func test_sessionNotSavedNotShown_isOfferedAgainToTheNextStream() async {
        let store = FakeTrackingSessionStore()
        store.setSaveFailing(true)
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates, sessionStore: store)
        let viewModel = subject.viewModel
        let firstRecorder = EventRecorder(viewModel.makeEventsStream())
        viewModel.onStartClicked()
        await waitUntil { firstRecorder.events.contains(where: \.isSessionNotSaved) }
        firstRecorder.stop()

        let secondRecorder = EventRecorder(viewModel.makeEventsStream())
        defer { secondRecorder.stop() }

        await waitUntil { secondRecorder.events.contains(where: \.isSessionNotSaved) }
        XCTAssertEqual(secondRecorder.events.filter(\.isSessionNotSaved).count, 1, "got \(secondRecorder.events)")
    }

    /// Finish while the warning is still on screen (its OK not yet tapped): the warning belongs to the ended session, so
    /// the next stream (the next Tracking screen) is not offered it.
    func test_finishBeforeTheWarningWasShown_offersNoWarningToTheNextStream() async {
        let store = FakeTrackingSessionStore()
        store.setSaveFailing(true)
        let subject = makeSubject(
            updates: TrackingFixtures.movingUpdates,
            profile: UserProfile(weightKg: Self.weightKg),
            sessionStore: store
        )
        let viewModel = subject.viewModel
        let firstRecorder = EventRecorder(viewModel.makeEventsStream())
        viewModel.onStartClicked()
        await waitUntil { firstRecorder.events.contains(where: \.isSessionNotSaved) }
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count && viewModel.calories != nil }

        viewModel.onStopClicked()
        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: nil) { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount == 1 }
        firstRecorder.stop()

        let warning = subject.trackingSessionManager.unsavedSessionWarning
        XCTAssertFalse(warning.isRaised.value.boolValue, "the finished session's warning is still raised")
        let nextRecorder = EventRecorder(viewModel.makeEventsStream())
        defer { nextRecorder.stop() }
        await Task.yield()
        XCTAssertFalse(nextRecorder.events.contains(where: \.isSessionNotSaved), "got \(nextRecorder.events)")
    }

    func test_succeedingSaves_emitNoSessionNotSaved() async {
        let store = FakeTrackingSessionStore()
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates, sessionStore: store)
        let viewModel = subject.viewModel
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }
        await waitUntil { store.storedSession != nil }

        XCTAssertFalse(recorder.events.contains(where: \.isSessionNotSaved), "got \(recorder.events)")
    }
}

private extension TrackingUiEvent {
    var isSessionNotSaved: Bool {
        guard case .sessionNotSaved = self else { return false }
        return true
    }
}
