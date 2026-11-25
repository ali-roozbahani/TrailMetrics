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
        XCTAssertFalse(subject.trackingSessionManager.unsavedSessionWarning.value.boolValue, "shown, so cleared")
        XCTAssertNil(store.storedSession)
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
