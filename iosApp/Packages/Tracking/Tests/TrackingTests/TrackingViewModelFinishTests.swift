//
//  TrackingViewModelFinishTests.swift
//  TrackingTests
//
//  Repeated Finish: one save and one `onSaved` per finished session, a retry after a
//  failed save, and a new save after a new session.
//

import SharedKit
import TestSupport
import Tracking
import XCTest

@MainActor
final class TrackingViewModelFinishTests: TrackingTestCase {

    func test_onFinishClicked_twiceBackToBack_savesOnceAndCallsOnSavedOnce() async {
        let activityHistoryRepository = FakeActivityHistoryRepository()
        let viewModel = await makeFinishedSubject(activityHistoryRepository: activityHistoryRepository).viewModel

        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "first") { onSavedCallCount += 1 }
        viewModel.onFinishClicked(snapshotFilePath: "second") { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount > 0 }

        await finishBarrier(sharing: activityHistoryRepository)
        XCTAssertEqual(onSavedCallCount, 1)
        XCTAssertEqual(
            activityHistoryRepository.savedActivities.map(\.snapshotFilePath).filter { $0 != "barrier" },
            ["first"]
        )
    }

    func test_onFinishClicked_afterFailedSave_savesAgain() async {
        let activityHistoryRepository = FakeActivityHistoryRepository()
        activityHistoryRepository.setFailing(true)
        let viewModel = await makeFinishedSubject(activityHistoryRepository: activityHistoryRepository).viewModel
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "failed") { onSavedCallCount += 1 }
        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        guard case .showError(let error) = recorder.events.first else {
            return XCTFail("Expected showError, got \(recorder.events)")
        }
        XCTAssertTrue(error is RouteUiErrorGeneral)
        XCTAssertEqual(onSavedCallCount, 0)
        XCTAssertTrue(activityHistoryRepository.savedActivities.isEmpty)

        activityHistoryRepository.setFailing(false)
        viewModel.onFinishClicked(snapshotFilePath: "retried") { onSavedCallCount += 1 }

        await waitUntil { onSavedCallCount > 0 }
        await Task.yield()
        XCTAssertEqual(onSavedCallCount, 1)
        XCTAssertEqual(activityHistoryRepository.savedActivities.map(\.snapshotFilePath), ["retried"])
        XCTAssertEqual(recorder.events.count, 1)
    }

    func test_onFinishClicked_afterStartOfNewSession_savesAgain() async {
        let activityHistoryRepository = FakeActivityHistoryRepository()
        let subject = await makeFinishedSubject(activityHistoryRepository: activityHistoryRepository)
        let viewModel = subject.viewModel
        var onSavedCallCount = 0
        viewModel.onFinishClicked(snapshotFilePath: "first") { onSavedCallCount += 1 }
        await waitUntil { onSavedCallCount == 1 }

        // Stop cancelled the ViewModel's state observation (board record
        // document-ios-start-after-stop-limitation), so wait on the session manager's
        // second location collection instead; Stop reads the manager's state directly.
        viewModel.onStartClicked()
        await waitUntil { subject.locationRepository.observeCallCount == 2 }
        viewModel.onStopClicked()
        viewModel.onFinishClicked(snapshotFilePath: "second") { onSavedCallCount += 1 }

        await waitUntil { onSavedCallCount == 2 }
        await Task.yield()
        XCTAssertEqual(onSavedCallCount, 2)
        XCTAssertEqual(activityHistoryRepository.savedActivities.map(\.snapshotFilePath), ["first", "second"])
    }

    // MARK: - Helpers

    /// Barrier: a valid finish on a second ViewModel sharing the same repository, saved as
    /// "barrier". A save another ViewModel had already started reaches the repository first.
    private func finishBarrier(sharing activityHistoryRepository: FakeActivityHistoryRepository) async {
        let barrier = await makeFinishedSubject(activityHistoryRepository: activityHistoryRepository)
        var barrierOnSavedCallCount = 0
        barrier.viewModel.onFinishClicked(snapshotFilePath: "barrier") { barrierOnSavedCallCount += 1 }
        await waitUntil { barrierOnSavedCallCount > 0 }
        await Task.yield()
    }
}
