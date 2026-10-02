//
//  RouteViewModelGenerationTests.swift
//  RouteTests
//
//  Route generation while a directions request is still running: the in-flight guard,
//  cancellation by Reset and waypoint changes, and discarding a cancelled result. The
//  directions fake holds each request until the test releases it.
//

import Route
import SharedKit
import TestSupport
import XCTest

@MainActor
final class RouteViewModelGenerationTests: XCTestCase {

    private static let staleRoute = RouteFixtures.route
    private static let freshRoute = Route(points: RouteFixtures.route.points, distanceMeters: 9_999)

    // XCTest creates a new instance per test, so each test gets its own fake.
    private let directionsRepository = FakeDirectionsRepository(
        routes: [RouteViewModelGenerationTests.staleRoute, RouteViewModelGenerationTests.freshRoute]
    )

    override func setUp() async throws {
        try await super.setUp()
        directionsRepository.holdRequests()
    }

    override func tearDown() async throws {
        directionsRepository.releaseAll()
        try await super.tearDown()
    }

    func test_onGenerateRouteClicked_whileGenerating_isIgnored() async {
        let (viewModel, recorder) = await makeGeneratingViewModel()
        defer { recorder.stop() }

        viewModel.onGenerateRouteClicked()
        await roundTrip(viewModel, recorder)

        XCTAssertEqual(directionsRepository.requests.count, 1)
        XCTAssertTrue(viewModel.isLoading)
        directionsRepository.release(requestAt: 0)
        await waitUntil { viewModel.generatedRoute != nil }
        XCTAssertEqual(viewModel.generatedRoute, Self.staleRoute)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(directionsRepository.requests.count, 1)
    }

    func test_onResetClicked_whileGenerating_discardsResultAndStopsLoading() async {
        let (viewModel, recorder) = await makeGeneratingViewModel()
        defer { recorder.stop() }

        viewModel.onResetClicked()
        XCTAssertFalse(viewModel.isLoading)

        await releaseStaleRequest(viewModel, recorder)
        XCTAssertNil(viewModel.generatedRoute)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(recorder.events.compactMap(\.shownError).count, 0, "got \(recorder.events)")
    }

    func test_onResetClicked_whileGeneratingRequestFails_emitsNoError() async {
        let failure = RouteError.DirectionsApiError(apiException: KotlinThrowable(message: "HTTP 500"))
        let failingRepository = FakeDirectionsRepository(failure: failure)
        failingRepository.holdRequests()
        defer { failingRepository.releaseAll() }
        let (viewModel, recorder) = await makeGeneratingViewModel(directionsRepository: failingRepository)
        defer { recorder.stop() }

        viewModel.onResetClicked()

        await releaseStaleRequest(from: failingRepository, viewModel, recorder)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(recorder.events.compactMap(\.shownError).count, 0, "got \(recorder.events)")
    }

    func test_onMapTapped_whileGenerating_discardsResultAndStopsLoading() async {
        let (viewModel, recorder) = await makeGeneratingViewModel()
        defer { recorder.stop() }

        viewModel.onMapTapped(RouteFixtures.waypoint(3))
        XCTAssertFalse(viewModel.isLoading)

        await releaseStaleRequest(viewModel, recorder)
        XCTAssertNil(viewModel.generatedRoute)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.waypoints.count, 4)
        XCTAssertEqual(recorder.events.compactMap(\.shownError).count, 0, "got \(recorder.events)")
    }

    func test_onWaypointRemoved_whileGenerating_discardsResultAndStopsLoading() async {
        let (viewModel, recorder) = await makeGeneratingViewModel()
        defer { recorder.stop() }

        viewModel.onWaypointRemoved(viewModel.waypoints[0])
        XCTAssertFalse(viewModel.isLoading)

        await releaseStaleRequest(viewModel, recorder)
        XCTAssertNil(viewModel.generatedRoute)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.waypoints.count, 2)
        XCTAssertEqual(recorder.events.compactMap(\.shownError).count, 0, "got \(recorder.events)")
    }

    func test_onGenerateRouteClicked_afterResetWhileOldRequestRuns_landsOnlyNewResult() async {
        let (viewModel, recorder) = await makeGeneratingViewModel()
        defer { recorder.stop() }
        viewModel.onResetClicked()
        await waitUntil { viewModel.startPoint != nil }
        tapWaypoints(3, on: viewModel)

        viewModel.onGenerateRouteClicked()
        await waitUntil { self.directionsRepository.requests.count == 2 }

        // The old generation finishing late must not end the new one's loading state.
        await releaseStaleRequest(viewModel, recorder)
        XCTAssertNil(viewModel.generatedRoute)
        XCTAssertTrue(viewModel.isLoading)

        directionsRepository.release(requestAt: 1)
        await waitUntil { viewModel.generatedRoute != nil }
        XCTAssertEqual(viewModel.generatedRoute, Self.freshRoute)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(recorder.events.compactMap(\.shownError).count, 0, "got \(recorder.events)")
    }

    func test_onMapTapped_withGeneratedRoute_clearsRouteAndAddsWaypoint() async {
        let viewModel = await makeViewModelWithGeneratedRoute()

        viewModel.onMapTapped(RouteFixtures.waypoint(3))

        XCTAssertNil(viewModel.generatedRoute)
        XCTAssertEqual(viewModel.waypoints.map(\.coordinates), (0..<4).map(RouteFixtures.waypoint))
        XCTAssertEqual(viewModel.waypoints.map(\.order), [0, 1, 2, 3])
    }

    // MARK: - Helpers

    /// A ViewModel with its start point and three waypoints whose first Generate is held
    /// in the directions fake, plus a recorder of its events.
    private func makeGeneratingViewModel(
        directionsRepository: FakeDirectionsRepository? = nil
    ) async -> (RouteViewModel, EventRecorder) {
        let directionsRepository = directionsRepository ?? self.directionsRepository
        let viewModel = makeViewModel(directionsRepository: directionsRepository)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        await waitUntil { viewModel.startPoint != nil }
        tapWaypoints(3, on: viewModel)
        viewModel.onGenerateRouteClicked()
        await waitUntil { directionsRepository.requests.count == 1 }
        XCTAssertTrue(viewModel.isLoading)
        return (viewModel, recorder)
    }

    /// Lets the first (stale) request return, then waits until its result had time to land.
    private func releaseStaleRequest(
        from directionsRepository: FakeDirectionsRepository? = nil,
        _ viewModel: RouteViewModel,
        _ recorder: EventRecorder
    ) async {
        let directionsRepository = directionsRepository ?? self.directionsRepository
        directionsRepository.release(requestAt: 0)
        await waitUntil { directionsRepository.completedRequestCount >= 1 }
        await roundTrip(viewModel, recorder)
    }

    /// Barrier: a full Swift → Kotlin → fake → Swift round trip through the ViewModel,
    /// started now. Without a profile, Start Tracking emits `.requestUserProfile`. A
    /// result the directions fake already returned reaches the ViewModel before this does.
    private func roundTrip(_ viewModel: RouteViewModel, _ recorder: EventRecorder) async {
        let requestCount = recorder.events.filter(\.isRequestUserProfile).count
        viewModel.onStartTrackingClicked()
        await waitUntil { recorder.events.filter(\.isRequestUserProfile).count > requestCount }
    }
}

private extension RouteUiEvent {
    var isRequestUserProfile: Bool {
        guard case .requestUserProfile = self else { return false }
        return true
    }
}
