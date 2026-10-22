//
//  RouteViewModelUnreadableProfileTests.swift
//  RouteTests
//
//  A stored profile that cannot be decoded (the Kotlin StoredUserProfileUnreadableException) is
//  treated like a missing one, so the user can enter a new profile, and is shown once as a
//  general error.
//

import Route
import SharedKit
import TestSupport
import XCTest

@MainActor
final class RouteViewModelUnreadableProfileTests: XCTestCase {

    func test_load_withUnreadableProfile_emitsOneGeneralErrorAndLeavesProfileUnset() async {
        let userProfileRepository = FakeUserProfileRepository()
        userProfileRepository.setUnreadable(true)
        let viewModel = makeViewModel(userProfileRepository: userProfileRepository)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await waitUntil { !recorder.events.isEmpty }

        XCTAssertEqual(recorder.events.count, 1, "got \(recorder.events)")
        XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorGeneral, "got \(recorder.events)")
        XCTAssertNil(viewModel.userProfile)
    }

    func test_onStartTrackingClicked_withUnreadableProfile_requestsProfileWithoutSecondError() async {
        let userProfileRepository = FakeUserProfileRepository()
        userProfileRepository.setUnreadable(true)
        let viewModel = await makeViewModelWithGeneratedRoute(userProfileRepository: userProfileRepository)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        // The load's own error comes first and is the only error.
        await waitUntil { !recorder.events.isEmpty }

        viewModel.onStartTrackingClicked()
        await waitUntil { recorder.events.count == 2 }

        XCTAssertEqual(recorder.events.map(\.kind), ["showError", "requestUserProfile"], "got \(recorder.events)")
    }

    func test_saveUserProfile_afterUnreadableProfile_replacesItAndStartTrackingNavigates() async {
        let userProfileRepository = FakeUserProfileRepository()
        userProfileRepository.setUnreadable(true)
        let viewModel = await makeViewModelWithGeneratedRoute(userProfileRepository: userProfileRepository)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        await waitUntil { !recorder.events.isEmpty }

        viewModel.saveUserProfile(weightKg: 72.5)
        await waitUntil { viewModel.userProfile != nil }
        viewModel.onStartTrackingClicked()
        await waitUntil { recorder.events.count == 2 }

        XCTAssertEqual(userProfileRepository.savedProfiles.map(\.weightKg), [72.5])
        XCTAssertEqual(recorder.events.map(\.kind), ["showError", "navigateToTracking"], "got \(recorder.events)")
    }

    func test_onResetClicked_afterSavingNewProfile_showsNoError() async {
        let userProfileRepository = FakeUserProfileRepository()
        userProfileRepository.setUnreadable(true)
        let viewModel = makeViewModel(userProfileRepository: userProfileRepository)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        await waitUntil { !recorder.events.isEmpty }
        viewModel.saveUserProfile(weightKg: 72.5)
        await waitUntil { viewModel.userProfile != nil }
        let readCount = userProfileRepository.getUserProfileCallCount

        viewModel.onResetClicked()
        await waitUntil { userProfileRepository.getUserProfileCallCount > readCount && viewModel.userProfile != nil }

        XCTAssertEqual(recorder.events.map(\.kind), ["showError"], "got \(recorder.events)")
        XCTAssertEqual(viewModel.userProfile?.weightKg, 72.5)
    }
}

private extension RouteUiEvent {
    var kind: String {
        switch self {
        case .showError: "showError"
        case .requestUserProfile: "requestUserProfile"
        case .navigateToTracking: "navigateToTracking"
        }
    }
}
