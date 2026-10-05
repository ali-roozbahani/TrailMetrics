//
//  RouteViewModelStartTrackingTests.swift
//  RouteTests
//
//  Start Tracking tapped again while the first tap's profile read is still running: at most
//  one event for both taps, and the guard released on every exit (navigation, the profile
//  request, a failed read) so that a later, separate tap works again. The profile fake holds
//  the read until the test releases it.
//

import Route
import SharedKit
import TestSupport
import XCTest

@MainActor
final class RouteViewModelStartTrackingTests: XCTestCase {

    private let profile = UserProfile(weightKg: 70)

    func test_onStartTrackingClicked_tappedTwiceWhileProfileReadRuns_navigatesOnce() async {
        let userProfileRepository = FakeUserProfileRepository(profile: profile)
        var viewModel = await makeViewModelWithGeneratedRoute(userProfileRepository: userProfileRepository)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await tapTwiceWhileProfileReadIsHeld(&viewModel, userProfileRepository)

        // Released after navigating: a later tap navigates again, and its event comes after
        // everything the two taps emitted.
        viewModel.onActivityTypeSelected(.cycling)
        viewModel.onStartTrackingClicked()
        await waitUntil { recorder.events.last?.navigationActivityType == .cycling }
        XCTAssertEqual(
            recorder.events.map(\.navigationActivityType),
            [.running, .cycling],
            "one navigation for the double tap, then one for the later tap, got \(recorder.events)"
        )
    }

    func test_onStartTrackingClicked_tappedTwiceWithoutProfile_requestsProfileOnce() async {
        let userProfileRepository = FakeUserProfileRepository()
        var viewModel = await makeViewModelWithGeneratedRoute(userProfileRepository: userProfileRepository)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await tapTwiceWhileProfileReadIsHeld(&viewModel, userProfileRepository)

        // Released after requesting the profile: the profile dialog saves, and a later tap navigates.
        viewModel.saveUserProfile(weightKg: 70)
        await waitUntil { viewModel.userProfile != nil }
        viewModel.onStartTrackingClicked()
        await waitUntil { recorder.events.last?.navigationActivityType != nil }
        XCTAssertEqual(
            recorder.events.map(\.kind),
            ["requestUserProfile", "navigateToTracking"],
            "one profile request for the double tap, then the later tap's navigation, got \(recorder.events)"
        )
    }

    func test_onStartTrackingClicked_tappedTwiceWhileProfileReadFails_showsOneErrorAndLaterTapWorks() async {
        let userProfileRepository = FakeUserProfileRepository(profile: profile)
        var viewModel = await makeViewModelWithGeneratedRoute(userProfileRepository: userProfileRepository)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        await waitUntil { viewModel.userProfile != nil }
        userProfileRepository.setFailing(true)

        await tapTwiceWhileProfileReadIsHeld(&viewModel, userProfileRepository)

        // Released after the failed read: a later tap navigates.
        userProfileRepository.setFailing(false)
        viewModel.onStartTrackingClicked()
        await waitUntil { recorder.events.last?.navigationActivityType != nil }
        XCTAssertEqual(
            recorder.events.map(\.kind),
            ["showError", "navigateToTracking"],
            "one error for the double tap, then the later tap's navigation, got \(recorder.events)"
        )
        XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorGeneral, "got \(recorder.events)")
    }

    func test_onStartTrackingClicked_afterFirstTapFinished_navigatesAgain() async {
        let userProfileRepository = FakeUserProfileRepository(profile: profile)
        let viewModel = await makeViewModelWithGeneratedRoute(userProfileRepository: userProfileRepository)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        viewModel.onStartTrackingClicked()
        await waitUntil { recorder.events.count == 1 }
        // Like returning from Tracking to Route and tapping Start Tracking again.
        viewModel.onStartTrackingClicked()

        await waitUntil { recorder.events.count == 2 }
        XCTAssertEqual(
            recorder.events.map(\.navigationActivityType),
            [.running, .running],
            "got \(recorder.events)"
        )
    }

    // MARK: - Helpers

    /// Taps Start Tracking, waits until that tap's profile read is held in the fake, taps
    /// again, releases the read and waits until every Task the ViewModel started has finished.
    /// The caller holds the only reference to `viewModel` (see `waitUntilOnlyReference`).
    private func tapTwiceWhileProfileReadIsHeld(
        _ viewModel: inout RouteViewModel,
        _ userProfileRepository: FakeUserProfileRepository
    ) async {
        await waitUntilOnlyReference(&viewModel)
        let readCount = userProfileRepository.getUserProfileCallCount
        userProfileRepository.holdReads()
        defer { userProfileRepository.releaseReads() }

        viewModel.onStartTrackingClicked()
        await waitUntil { userProfileRepository.getUserProfileCallCount == readCount + 1 }
        viewModel.onStartTrackingClicked()
        userProfileRepository.releaseReads()

        await waitUntilOnlyReference(&viewModel)
        XCTAssertEqual(
            userProfileRepository.getUserProfileCallCount,
            readCount + 1,
            "the second tap reads the profile again"
        )
    }
}

private extension RouteUiEvent {
    var navigationActivityType: ActivityType? {
        guard case let .navigateToTracking(_, _, activityType) = self else { return nil }
        return activityType
    }

    var kind: String {
        switch self {
        case .showError: "showError"
        case .requestUserProfile: "requestUserProfile"
        case .navigateToTracking: "navigateToTracking"
        }
    }
}
