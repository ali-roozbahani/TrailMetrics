//
//  RouteViewModelUnreadableProfileTests.swift
//  RouteTests
//
//  A stored profile that cannot be decoded (the Kotlin StoredUserProfileUnreadableException) is
//  treated like a missing one, so the user can enter a new profile, and is shown once as a
//  general error.
//
//  These tests use the real UserProfileRepositoryImpl on UserDefaults, holding a broken string:
//  a Swift fake cannot throw that exception, because SKIE wraps every error a Swift class throws
//  into a generic Kotlin exception, so the ViewModel would never see the typed one.
//

import Foundation
import Route
import SharedKit
import TestSupport
import XCTest

@MainActor
final class RouteViewModelUnreadableProfileTests: XCTestCase {

    private static let storageKey = "user_profile"

    private let scope = SwiftTestScope()
    private var userProfileRepository: UserProfileRepositoryImpl?

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        UserDefaults.standard.set("{ not a valid json", forKey: Self.storageKey)
        // The scope only lends its Dispatchers.Default to the repository.
        let dispatcher = try XCTUnwrap(
            scope.coroutineContext.get(key: Kotlinx_coroutines_coreCoroutineDispatcher.Key.shared)
                as? Kotlinx_coroutines_coreCoroutineDispatcher
        )
        userProfileRepository = UserProfileRepositoryImpl(storage: KeyValueStorage(), ioDispatcher: dispatcher)
    }

    override func tearDown() async throws {
        scope.cancel()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    func test_load_withUnreadableProfile_emitsOneGeneralErrorAndLeavesProfileUnset() async throws {
        let viewModel = try await makeViewModelWithGeneratedRoute()
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await waitUntil { !recorder.events.isEmpty }

        XCTAssertEqual(recorder.events.map(\.kind), ["showError"], "got \(recorder.events)")
        XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorGeneral, "got \(recorder.events)")
        XCTAssertNil(viewModel.userProfile)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: Self.storageKey),
            "{ not a valid json",
            "the broken value stays in storage"
        )
    }

    func test_onStartTrackingClicked_withUnreadableProfile_requestsProfileWithoutSecondError() async throws {
        let viewModel = try await makeViewModelWithGeneratedRoute()
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        await waitUntil { viewModel.generatedRoute != nil && !recorder.events.isEmpty }

        viewModel.onStartTrackingClicked()
        await waitUntil { recorder.events.count == 2 }

        // The load's own error is the only error; the tap is treated as a missing profile.
        XCTAssertEqual(recorder.events.map(\.kind), ["showError", "requestUserProfile"], "got \(recorder.events)")
    }

    func test_saveUserProfile_afterUnreadableProfile_replacesItAndStartTrackingNavigates() async throws {
        let viewModel = try await makeViewModelWithGeneratedRoute()
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        await waitUntil { viewModel.generatedRoute != nil && !recorder.events.isEmpty }

        viewModel.saveUserProfile(weightKg: 72.5)
        await waitUntil { viewModel.userProfile != nil }
        viewModel.onStartTrackingClicked()
        await waitUntil { recorder.events.count == 2 }

        XCTAssertEqual(recorder.events.map(\.kind), ["showError", "navigateToTracking"], "got \(recorder.events)")
        XCTAssertEqual(UserDefaults.standard.string(forKey: Self.storageKey), #"{"weightKg":72.5}"#)
    }

    func test_onResetClicked_afterSavingNewProfile_showsNoError() async throws {
        let viewModel = try await makeViewModelWithGeneratedRoute()
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        await waitUntil { !recorder.events.isEmpty }
        viewModel.saveUserProfile(weightKg: 72.5)
        await waitUntil { viewModel.userProfile != nil }

        viewModel.onResetClicked()
        // Reset clears the profile, then the load puts the saved one back.
        await waitUntil { viewModel.userProfile == nil }
        await waitUntil { viewModel.userProfile != nil }

        XCTAssertEqual(recorder.events.map(\.kind), ["showError"], "got \(recorder.events)")
        XCTAssertEqual(viewModel.userProfile?.weightKg, 72.5)
    }

    // MARK: - Helpers

    private func makeViewModelWithGeneratedRoute() async throws -> RouteViewModel {
        let repository = try XCTUnwrap(userProfileRepository)
        let viewModel = RouteViewModel(
            getCurrentLocationUseCase: GetCurrentLocationUseCase(
                locationRepository: FakeLocationRepository(location: RouteFixtures.startPoint)
            ),
            generateClosedRouteUseCase: GenerateClosedRouteUseCase(
                directionsRepository: FakeDirectionsRepository(route: RouteFixtures.route)
            ),
            userProfileRepository: repository
        )
        await waitUntil { viewModel.startPoint != nil }
        tapWaypoints(3, on: viewModel)
        viewModel.onGenerateRouteClicked()
        await waitUntil { viewModel.generatedRoute != nil }
        return viewModel
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
