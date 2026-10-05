//
//  TrackingViewModelPendingEventsTests.swift
//  TrackingTests
//
//  Events emitted while no `makeEventsStream()` consumer is active: before TrackingView's
//  `.task` first runs, and after a consumer was cancelled. Each test waits with
//  `waitUntilOnlyReference` until the ViewModel's own Tasks have emitted, then creates the
//  stream, so the event can only arrive if the ViewModel kept it. The ViewModel is taken out
//  of its subject so that the test holds its only reference.
//

import SharedKit
import TestSupport
import Tracking
import XCTest

@MainActor
final class TrackingViewModelPendingEventsTests: TrackingTestCase {

    /// TrackingViewModel's limit on events kept while no consumer is active.
    private static let maxPendingEvents = 10

    func test_init_profileLoadFailsBeforeStreamExists_deliversErrorToFirstStream() async {
        var viewModel = makeSubject(
            profile: UserProfile(weightKg: Self.weightKg),
            isProfileStorageFailing: true
        ).viewModel
        await waitUntilOnlyReference(&viewModel)

        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorGeneral, "got \(recorder.events)")
    }

    /// Like TrackingView's `.task` being cancelled, and a new `.task` (a new stream) after it.
    func test_eventAfterConsumerCancelled_isDeliveredOnceToNextStreamOnly() async {
        let activityHistoryRepository = FakeActivityHistoryRepository()
        activityHistoryRepository.setFailing(true)
        var viewModel = await makeFinishedSubject(activityHistoryRepository: activityHistoryRepository).viewModel
        let firstRecorder = EventRecorder(viewModel.makeEventsStream())
        viewModel.onFinishClicked(snapshotFilePath: nil) {}
        await waitUntil { !firstRecorder.events.isEmpty }
        firstRecorder.stop()

        viewModel.onFinishClicked(snapshotFilePath: nil) {}
        await waitUntilOnlyReference(&viewModel)
        let secondRecorder = EventRecorder(viewModel.makeEventsStream())
        await waitUntil { !secondRecorder.events.isEmpty }
        secondRecorder.stop()

        let thirdRecorder = EventRecorder(viewModel.makeEventsStream())
        viewModel.onFinishClicked(snapshotFilePath: nil) {}

        await waitUntil { !thirdRecorder.events.isEmpty }
        await waitUntilOnlyReference(&viewModel)
        await thirdRecorder.stopAndDrain()
        XCTAssertEqual(thirdRecorder.events.count, 1, "the kept event is not delivered again")
        XCTAssertEqual(firstRecorder.events.count, 1)
        XCTAssertEqual(secondRecorder.events.count, 1)
        for recorder in [firstRecorder, secondRecorder, thirdRecorder] {
            XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorGeneral, "got \(recorder.events)")
        }
        XCTAssertTrue(activityHistoryRepository.savedActivities.isEmpty)
    }

    func test_eventsWithoutConsumer_keepOnlyTheNewestUpToTheLimit() async {
        let activityHistoryRepository = FakeActivityHistoryRepository()
        activityHistoryRepository.setFailing(true)
        var viewModel = await makeFinishedSubject(activityHistoryRepository: activityHistoryRepository).viewModel
        // One more failed save than the limit; each must fail before Finish is accepted again.
        for _ in 0...Self.maxPendingEvents {
            viewModel.onFinishClicked(snapshotFilePath: nil) {}
            await waitUntilOnlyReference(&viewModel)
        }

        let recorder = EventRecorder(viewModel.makeEventsStream())
        await recorder.stopAndDrain()

        XCTAssertEqual(recorder.events.count, Self.maxPendingEvents, "got \(recorder.events)")
        XCTAssertTrue(recorder.events.allSatisfy { $0.shownError is RouteUiErrorGeneral }, "got \(recorder.events)")
    }
}

private extension TrackingUiEvent {
    var shownError: (any RouteUiError)? {
        guard case .showError(let error) = self else { return nil }
        return error
    }
}
