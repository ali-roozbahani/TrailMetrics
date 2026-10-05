//
//  RouteViewModelPendingEventsTests.swift
//  RouteTests
//
//  Events emitted while no `makeEventsStream()` consumer is active: before RouteView's
//  `.task` first runs, and while a pushed screen has cancelled it. Each test waits with
//  `waitUntilOnlyReference` until the ViewModel's own Tasks have emitted, then creates the
//  stream, so the event can only arrive if the ViewModel kept it.
//

import Route
import SharedKit
import TestSupport
import XCTest

@MainActor
final class RouteViewModelPendingEventsTests: XCTestCase {

    /// RouteViewModel's limit on events kept while no consumer is active.
    private static let maxPendingEvents = 10

    func test_init_profileLoadFailsBeforeStreamExists_deliversErrorToFirstStream() async {
        let userProfileRepository = FakeUserProfileRepository(isFailing: true)
        var viewModel = makeViewModel(userProfileRepository: userProfileRepository)
        await waitUntilOnlyReference(&viewModel)
        XCTAssertEqual(userProfileRepository.getUserProfileCallCount, 1)

        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorGeneral, "got \(recorder.events)")
    }

    func test_init_locationLoadFailsBeforeStreamExists_deliversErrorToFirstStream() async {
        let locationRepository = FakeLocationRepository(failure: RouteError.MissingLocationPermission())
        var viewModel = makeViewModel(locationRepository: locationRepository)
        await waitUntilOnlyReference(&viewModel)
        XCTAssertEqual(locationRepository.getCurrentLocationCallCount, 1)

        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertTrue(
            recorder.events.first?.shownError is RouteUiErrorMissingLocationPermission,
            "got \(recorder.events)"
        )
    }

    func test_eventsWithoutConsumer_areDeliveredInOrderBeforeLaterEvents() async {
        let userProfileRepository = FakeUserProfileRepository()
        var viewModel = makeViewModel(
            locationRepository: FakeLocationRepository(failure: RouteError.MissingLocationPermission()),
            userProfileRepository: userProfileRepository
        )
        await waitUntilOnlyReference(&viewModel)
        viewModel.onStartTrackingClicked()
        await waitUntilOnlyReference(&viewModel)

        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        userProfileRepository.setFailing(true)
        viewModel.onStartTrackingClicked()

        await waitUntil { recorder.events.count == 3 }
        guard recorder.events.count == 3 else {
            return XCTFail("Expected three events, got \(recorder.events)")
        }
        XCTAssertTrue(recorder.events[0].shownError is RouteUiErrorMissingLocationPermission, "got \(recorder.events)")
        guard case .requestUserProfile = recorder.events[1] else {
            return XCTFail("Expected requestUserProfile second, got \(recorder.events)")
        }
        XCTAssertTrue(recorder.events[2].shownError is RouteUiErrorGeneral, "got \(recorder.events)")
    }

    /// Like RouteView's `.task` being cancelled while Tracking is pushed over it, and a new
    /// `.task` (a new stream) each time RouteView is revealed again.
    func test_eventAfterConsumerCancelled_isDeliveredOnceToNextStreamOnly() async {
        let userProfileRepository = FakeUserProfileRepository()
        var viewModel = makeViewModel(userProfileRepository: userProfileRepository)
        await waitUntilOnlyReference(&viewModel)
        let firstRecorder = EventRecorder(viewModel.makeEventsStream())
        viewModel.onStartTrackingClicked()
        await waitUntil { !firstRecorder.events.isEmpty }
        firstRecorder.stop()

        viewModel.onStartTrackingClicked()
        await waitUntilOnlyReference(&viewModel)
        let secondRecorder = EventRecorder(viewModel.makeEventsStream())
        await waitUntil { !secondRecorder.events.isEmpty }
        guard case .requestUserProfile = secondRecorder.events.first else {
            return XCTFail("Expected requestUserProfile, got \(secondRecorder.events)")
        }
        secondRecorder.stop()

        let thirdRecorder = EventRecorder(viewModel.makeEventsStream())
        defer { thirdRecorder.stop() }
        userProfileRepository.setFailing(true)
        viewModel.onStartTrackingClicked()

        await waitUntil { !thirdRecorder.events.isEmpty }
        XCTAssertEqual(thirdRecorder.events.count, 1, "the kept event is not delivered again")
        XCTAssertTrue(thirdRecorder.events.first?.shownError is RouteUiErrorGeneral, "got \(thirdRecorder.events)")
        XCTAssertEqual(firstRecorder.events.count, 1)
        XCTAssertEqual(secondRecorder.events.count, 1)
    }

    func test_eventsWithoutConsumer_keepOnlyTheNewestUpToTheLimit() async {
        let userProfileRepository = FakeUserProfileRepository()
        var viewModel = makeViewModel(
            locationRepository: FakeLocationRepository(failure: RouteError.MissingLocationPermission()),
            userProfileRepository: userProfileRepository
        )
        await waitUntilOnlyReference(&viewModel)
        for _ in 0..<Self.maxPendingEvents {
            viewModel.onStartTrackingClicked()
        }
        await waitUntilOnlyReference(&viewModel)

        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        userProfileRepository.setFailing(true)
        viewModel.onStartTrackingClicked()

        // The live error comes after everything that was kept, so once it is in, all of it is.
        await waitUntil { recorder.events.last?.shownError is RouteUiErrorGeneral }
        XCTAssertEqual(recorder.events.count, Self.maxPendingEvents + 1, "got \(recorder.events)")
        let keptEvents = recorder.events.dropLast()
        XCTAssertTrue(
            keptEvents.allSatisfy { if case .requestUserProfile = $0 { true } else { false } },
            "the oldest event (the location error) is the one dropped, got \(recorder.events)"
        )
    }
}
