//
//  RouteViewModelTests.swift
//  RouteTests
//

import Route
import SharedKit
import TestSupport
import XCTest

@MainActor
final class RouteViewModelTests: XCTestCase {

    // MARK: - Init

    func test_init_loadsCurrentLocationAndUserProfile() async {
        let profile = UserProfile(weightKg: 70)
        let viewModel = makeViewModel(userProfileRepository: FakeUserProfileRepository(profile: profile))

        await waitUntil { viewModel.startPoint != nil && viewModel.userProfile != nil }

        XCTAssertEqual(viewModel.startPoint, RouteFixtures.startPoint)
        XCTAssertEqual(viewModel.userProfile, profile)
        XCTAssertEqual(viewModel.selectedActivityType, .running)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_init_missingLocationPermission_emitsShowErrorMissingLocationPermission() async {
        let viewModel = makeViewModel(
            locationRepository: FakeLocationRepository(failure: RouteError.MissingLocationPermission())
        )
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await waitUntil { !recorder.events.isEmpty }

        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorMissingLocationPermission)
        XCTAssertNil(viewModel.startPoint)
    }

    func test_init_locationUnavailable_emitsShowErrorLocationUnavailable() async {
        let viewModel = makeViewModel(
            locationRepository: FakeLocationRepository(failure: RouteError.LocationUnavailable(ex: nil))
        )
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await waitUntil { !recorder.events.isEmpty }

        XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorLocationUnavailable)
    }

    func test_init_profileLoadFails_emitsGeneralErrorAndLeavesProfileNil() async {
        let userProfileRepository = FakeUserProfileRepository(profile: UserProfile(weightKg: 70), isFailing: true)
        let viewModel = makeViewModel(userProfileRepository: userProfileRepository)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorGeneral)
        XCTAssertNil(viewModel.userProfile)

        userProfileRepository.setFailing(false)
        viewModel.onResetClicked()

        await waitUntil { viewModel.userProfile != nil }
        XCTAssertEqual(viewModel.userProfile, UserProfile(weightKg: 70))
        XCTAssertEqual(recorder.events.count, 1)
    }

    // MARK: - Waypoints

    func test_onMapTapped_appendsWaypointsInTapOrder() {
        let viewModel = makeViewModel()

        tapWaypoints(3, on: viewModel)

        XCTAssertEqual(viewModel.waypoints.map(\.coordinates), (0..<3).map(RouteFixtures.waypoint))
        XCTAssertEqual(viewModel.waypoints.map(\.order), [0, 1, 2])
    }

    func test_onWaypointRemoved_renumbersRemainingWaypointsAndClearsGeneratedRoute() async {
        let viewModel = await makeViewModelWithGeneratedRoute()

        viewModel.onWaypointRemoved(viewModel.waypoints[1])

        XCTAssertEqual(
            viewModel.waypoints.map(\.coordinates),
            [RouteFixtures.waypoint(0), RouteFixtures.waypoint(2)]
        )
        XCTAssertEqual(viewModel.waypoints.map(\.order), [0, 1])
        XCTAssertNil(viewModel.generatedRoute)
    }

    // MARK: - canGenerateRoute

    func test_canGenerateRoute_requiresStartPointAndThreeWaypoints() async {
        let viewModel = makeViewModel()
        tapWaypoints(3, on: viewModel)
        XCTAssertFalse(viewModel.canGenerateRoute, "no start point yet")

        await waitUntil { viewModel.startPoint != nil }
        viewModel.onWaypointRemoved(viewModel.waypoints[2])
        XCTAssertFalse(viewModel.canGenerateRoute, "only two waypoints")

        viewModel.onMapTapped(RouteFixtures.waypoint(2))
        XCTAssertTrue(viewModel.canGenerateRoute)
    }

    func test_canGenerateRoute_isFalseWhileGenerating() async {
        let viewModel = makeViewModel()
        await waitUntil { viewModel.startPoint != nil }
        tapWaypoints(3, on: viewModel)

        viewModel.onGenerateRouteClicked()

        XCTAssertTrue(viewModel.isLoading)
        XCTAssertFalse(viewModel.canGenerateRoute)
        await waitUntil { !viewModel.isLoading }
    }

    // MARK: - Generate

    func test_onGenerateRouteClicked_success_publishesRouteAndStopsLoading() async {
        let directionsRepository = FakeDirectionsRepository(route: RouteFixtures.route)
        let viewModel = makeViewModel(directionsRepository: directionsRepository)
        await waitUntil { viewModel.startPoint != nil }
        tapWaypoints(3, on: viewModel)

        viewModel.onGenerateRouteClicked()
        XCTAssertTrue(viewModel.isLoading)

        await waitUntil { viewModel.generatedRoute != nil }
        XCTAssertEqual(viewModel.generatedRoute, RouteFixtures.route)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(
            directionsRepository.requests,
            [.init(startPoint: RouteFixtures.startPoint, waypoints: (0..<3).map(RouteFixtures.waypoint))]
        )
    }

    func test_onGenerateRouteClicked_routeError_stopsLoadingAndEmitsGeneralError() async {
        let failure = RouteError.DirectionsApiError(apiException: KotlinThrowable(message: "HTTP 500"))
        let viewModel = makeViewModel(directionsRepository: FakeDirectionsRepository(failure: failure))
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        await waitUntil { viewModel.startPoint != nil }
        tapWaypoints(3, on: viewModel)

        viewModel.onGenerateRouteClicked()

        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorGeneral)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.generatedRoute)
    }

    // MARK: - Start tracking

    func test_onStartTrackingClicked_withoutProfile_emitsRequestUserProfile() async {
        let viewModel = await makeViewModelWithGeneratedRoute(userProfileRepository: FakeUserProfileRepository())
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        viewModel.onStartTrackingClicked()

        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        guard case .requestUserProfile = recorder.events.first else {
            return XCTFail("Expected requestUserProfile, got \(recorder.events)")
        }
    }

    func test_onStartTrackingClicked_withProfileAndRoute_emitsNavigateToTrackingWithRoutePayload() async {
        let viewModel = await makeViewModelWithGeneratedRoute(
            userProfileRepository: FakeUserProfileRepository(profile: UserProfile(weightKg: 70))
        )
        viewModel.onActivityTypeSelected(.cycling)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        viewModel.onStartTrackingClicked()

        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        guard case let .navigateToTracking(startPoint, plannedRoutePoints, activityType) = recorder.events.first else {
            return XCTFail("Expected navigateToTracking, got \(recorder.events)")
        }
        XCTAssertEqual(startPoint, RouteFixtures.startPoint)
        XCTAssertEqual(plannedRoutePoints, RouteFixtures.route.points.map(\.coordinates))
        XCTAssertEqual(activityType, .cycling)
    }

    func test_onStartTrackingClicked_profileLoadFails_emitsGeneralErrorWithoutNavigating() async {
        let userProfileRepository = FakeUserProfileRepository(profile: UserProfile(weightKg: 70))
        let viewModel = await makeViewModelWithGeneratedRoute(userProfileRepository: userProfileRepository)
        await waitUntil { viewModel.userProfile != nil }
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        userProfileRepository.setFailing(true)

        viewModel.onStartTrackingClicked()

        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorGeneral, "got \(recorder.events)")

        userProfileRepository.setFailing(false)
        viewModel.onStartTrackingClicked()

        await waitUntil { recorder.events.count == 2 }
        guard case .navigateToTracking = recorder.events.last else {
            return XCTFail("Expected navigateToTracking after the retry, got \(recorder.events)")
        }
    }

    // MARK: - Reset, profile, activity type

    func test_onResetClicked_restoresDefaultsAndReloadsLocationAndProfile() async {
        let locationRepository = FakeLocationRepository(location: RouteFixtures.startPoint)
        let userProfileRepository = FakeUserProfileRepository(profile: UserProfile(weightKg: 70))
        let viewModel = await makeViewModelWithGeneratedRoute(
            locationRepository: locationRepository,
            userProfileRepository: userProfileRepository
        )
        await waitUntil { viewModel.userProfile != nil }
        viewModel.onActivityTypeSelected(.walking)
        let movedLocation = Coordinates(latitude: 48.85, longitude: 2.35)
        locationRepository.setLocation(movedLocation)

        viewModel.onResetClicked()

        XCTAssertNil(viewModel.startPoint)
        XCTAssertTrue(viewModel.waypoints.isEmpty)
        XCTAssertNil(viewModel.generatedRoute)
        XCTAssertNil(viewModel.userProfile)
        XCTAssertEqual(viewModel.selectedActivityType, .running)
        XCTAssertFalse(viewModel.isLoading)

        await waitUntil { viewModel.startPoint != nil && viewModel.userProfile != nil }
        XCTAssertEqual(viewModel.startPoint, movedLocation)
        XCTAssertEqual(viewModel.userProfile, UserProfile(weightKg: 70))
        XCTAssertEqual(locationRepository.getCurrentLocationCallCount, 2)
        XCTAssertEqual(userProfileRepository.getUserProfileCallCount, 2)
    }

    func test_saveUserProfile_savesAndPublishesProfile() async {
        let userProfileRepository = FakeUserProfileRepository(profile: UserProfile(weightKg: 70))
        let viewModel = makeViewModel(userProfileRepository: userProfileRepository)
        // The initial profile load must finish first: if it resumes after the save, it
        // overwrites userProfile with what it read before the save (see the PR's Follow-ups).
        await waitUntil { viewModel.userProfile != nil }

        viewModel.saveUserProfile(weightKg: 82.5)

        await waitUntil { viewModel.userProfile == UserProfile(weightKg: 82.5) }
        XCTAssertEqual(userProfileRepository.savedProfiles, [UserProfile(weightKg: 82.5)])
    }

    func test_saveUserProfile_saveFails_emitsGeneralErrorAndKeepsPreviousProfile() async {
        let userProfileRepository = FakeUserProfileRepository(profile: UserProfile(weightKg: 70))
        let viewModel = makeViewModel(userProfileRepository: userProfileRepository)
        await waitUntil { viewModel.userProfile != nil }
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        userProfileRepository.setFailing(true)

        viewModel.saveUserProfile(weightKg: 82.5)

        await waitUntil { !recorder.events.isEmpty }
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertTrue(recorder.events.first?.shownError is RouteUiErrorGeneral)
        XCTAssertEqual(viewModel.userProfile, UserProfile(weightKg: 70))
        XCTAssertTrue(userProfileRepository.savedProfiles.isEmpty)

        userProfileRepository.setFailing(false)
        viewModel.saveUserProfile(weightKg: 82.5)

        await waitUntil { viewModel.userProfile == UserProfile(weightKg: 82.5) }
        XCTAssertEqual(userProfileRepository.savedProfiles, [UserProfile(weightKg: 82.5)])
        XCTAssertEqual(recorder.events.count, 1)
    }

    func test_onActivityTypeSelected_updatesSelection() {
        let viewModel = makeViewModel()

        viewModel.onActivityTypeSelected(.walking)

        XCTAssertEqual(viewModel.selectedActivityType, .walking)
    }

    // MARK: - Events stream

    func test_makeEventsStream_secondCallReturnsFreshWorkingStream() async {
        let viewModel = makeViewModel(userProfileRepository: FakeUserProfileRepository())
        let firstRecorder = EventRecorder(viewModel.makeEventsStream())
        viewModel.onStartTrackingClicked()
        await waitUntil { !firstRecorder.events.isEmpty }
        // Like RouteView's `.task` being cancelled when Tracking is pushed over it.
        firstRecorder.stop()

        let secondRecorder = EventRecorder(viewModel.makeEventsStream())
        defer { secondRecorder.stop() }
        viewModel.onStartTrackingClicked()

        await waitUntil { !secondRecorder.events.isEmpty }
        XCTAssertEqual(secondRecorder.events.count, 1)
        XCTAssertEqual(firstRecorder.events.count, 1)
        guard case .requestUserProfile = secondRecorder.events.first else {
            return XCTFail("Expected requestUserProfile, got \(secondRecorder.events)")
        }
    }
}
