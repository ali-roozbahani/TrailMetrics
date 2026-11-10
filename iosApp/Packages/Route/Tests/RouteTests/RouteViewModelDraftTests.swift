//
//  RouteViewModelDraftTests.swift
//  RouteTests
//
//  How RouteViewModel restores, saves and clears the stored route draft (process death). The
//  rules of when a write happens live in the Kotlin RouteDraftKeeper; these tests check that the
//  ViewModel calls it on every plan change and shows a restored plan.
//

import Route
import SharedKit
import TestSupport
import XCTest

@MainActor
final class RouteViewModelDraftTests: XCTestCase {

    private static let storedStart = Coordinates(latitude: 48.137, longitude: 11.575)

    private static let storedPlan = StoredRouteDraft(
        startPoint: storedStart,
        waypoints: (0..<3).map { RoutePoint(coordinates: RouteFixtures.waypoint($0), order: Int32($0)) },
        generatedRoute: RouteFixtures.route,
        activityType: .cycling
    )

    private var scopes: [SwiftTestScope] = []

    override func tearDown() async throws {
        scopes.forEach { $0.cancel() }
        scopes = []
        try await super.tearDown()
    }

    private func makeSubject(
        store: FakeRouteDraftStore,
        logger: FakeLogger = FakeLogger(),
        userProfileRepository: FakeUserProfileRepository = FakeUserProfileRepository()
    ) -> RouteViewModel {
        let scope = SwiftTestScope()
        scopes.append(scope)
        return makeViewModel(
            userProfileRepository: userProfileRepository,
            routeDraftKeeper: makeRouteDraftKeeper(store: store, logger: logger, scope: scope)
        )
    }

    private func draft(
        _ waypoints: [RoutePoint],
        route: Route? = nil,
        activityType: ActivityType = .running
    ) -> StoredRouteDraft {
        StoredRouteDraft(
            startPoint: RouteFixtures.startPoint,
            waypoints: waypoints,
            generatedRoute: route,
            activityType: activityType
        )
    }

    private func point(_ index: Int, order: Int) -> RoutePoint {
        RoutePoint(coordinates: RouteFixtures.waypoint(index), order: Int32(order))
    }

    // MARK: - Restore

    func test_init_restoresStoredPlanWithMarkersRouteAndActivityType() async {
        let store = FakeRouteDraftStore(stored: Self.storedPlan)
        let viewModel = makeSubject(store: store)

        await waitUntil { viewModel.waypoints.count == 3 }
        // The location load runs too: the plan's start point must survive it.
        await waitUntil { store.loadCount == 1 }

        XCTAssertEqual(viewModel.startPoint, Self.storedStart)
        XCTAssertEqual(viewModel.waypoints, Self.storedPlan.waypoints)
        XCTAssertEqual(viewModel.generatedRoute, RouteFixtures.route)
        XCTAssertEqual(viewModel.selectedActivityType, .cycling)
    }

    func test_init_restoringWritesNothing() async {
        let store = FakeRouteDraftStore(stored: Self.storedPlan)
        let viewModel = makeSubject(store: store)
        await waitUntil { viewModel.waypoints.count == 3 && viewModel.startPoint == Self.storedStart }

        // A later change is the barrier: it must be the first and only write.
        viewModel.onActivityTypeSelected(.walking)
        await waitUntil { !store.savedDrafts.isEmpty }

        XCTAssertEqual(
            store.savedDrafts,
            [
                StoredRouteDraft(
                    startPoint: Self.storedStart,
                    waypoints: Self.storedPlan.waypoints,
                    generatedRoute: RouteFixtures.route,
                    activityType: .walking
                )
            ]
        )
    }

    func test_init_storedPlanOfOnlyAStartPoint_takesTheCurrentLocation() async {
        let startOnly = StoredRouteDraft(
            startPoint: Self.storedStart,
            waypoints: [],
            generatedRoute: nil,
            activityType: .walking
        )
        let viewModel = makeSubject(store: FakeRouteDraftStore(stored: startOnly))

        await waitUntil {
            viewModel.selectedActivityType == .walking && viewModel.startPoint == RouteFixtures.startPoint
        }
    }

    func test_init_locationArrivingWhilePlanLoads_neitherSavesNorStopsRestore() async {
        let store = FakeRouteDraftStore(stored: Self.storedPlan)
        store.holdLoad()
        let viewModel = makeSubject(store: store)
        await waitUntil { viewModel.startPoint == RouteFixtures.startPoint && store.loadCount == 1 }

        store.releaseLoad()

        await waitUntil { viewModel.waypoints.count == 3 }
        XCTAssertEqual(viewModel.startPoint, Self.storedStart)
        XCTAssertTrue(store.savedDrafts.isEmpty)
    }

    func test_mapTappedBeforePlanLoads_winsAndLoadedPlanIsDropped() async {
        let store = FakeRouteDraftStore(stored: Self.storedPlan)
        store.holdLoad()
        let viewModel = makeSubject(store: store)
        await waitUntil { viewModel.startPoint != nil && store.loadCount == 1 }

        viewModel.onMapTapped(RouteFixtures.waypoint(5))
        store.releaseLoad()

        let expected = draft([point(5, order: 0)])
        await waitUntil { store.storedDraft == expected }
        XCTAssertEqual(viewModel.waypoints, [point(5, order: 0)])
        XCTAssertNil(viewModel.generatedRoute)
        XCTAssertEqual(viewModel.selectedActivityType, .running)
    }

    func test_failingRead_startsEmptyPlanWithoutErrorAndKeepsStoredRow() async {
        let store = FakeRouteDraftStore(stored: Self.storedPlan)
        store.setLoadFailing(true)
        let logger = FakeLogger()
        let viewModel = makeSubject(store: store, logger: logger)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }

        await waitUntil { !logger.messages.isEmpty && viewModel.startPoint != nil }

        XCTAssertEqual(viewModel.startPoint, RouteFixtures.startPoint)
        XCTAssertTrue(viewModel.waypoints.isEmpty)
        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(store.storedDraft, Self.storedPlan)

        // The first change replaces the unreadable plan; nothing was written before it.
        viewModel.onMapTapped(RouteFixtures.waypoint(0))
        await waitUntil { !store.savedDrafts.isEmpty }
        XCTAssertEqual(store.savedDrafts, [draft([point(0, order: 0)])])
    }

    // MARK: - Save

    func test_everyChangeOfWaypointsRouteAndActivityType_isSaved() async {
        let store = FakeRouteDraftStore()
        let viewModel = makeSubject(store: store)
        await waitUntil { viewModel.startPoint != nil }

        // Each change waits for its write, so no request replaces a waiting one.
        viewModel.onMapTapped(RouteFixtures.waypoint(0))
        await waitUntil { store.savedDrafts.count == 1 }
        viewModel.onMapTapped(RouteFixtures.waypoint(1))
        await waitUntil { store.savedDrafts.count == 2 }
        viewModel.onMapTapped(RouteFixtures.waypoint(2))
        await waitUntil { store.savedDrafts.count == 3 }
        viewModel.onActivityTypeSelected(.cycling)
        await waitUntil { store.savedDrafts.count == 4 }
        viewModel.onGenerateRouteClicked()
        await waitUntil { store.savedDrafts.count == 5 }
        viewModel.onWaypointRemoved(point(1, order: 1))
        await waitUntil { store.savedDrafts.count == 6 }

        let threePoints = [point(0, order: 0), point(1, order: 1), point(2, order: 2)]
        XCTAssertEqual(
            store.savedDrafts,
            [
                draft([point(0, order: 0)]),
                draft([point(0, order: 0), point(1, order: 1)]),
                draft(threePoints),
                draft(threePoints, activityType: .cycling),
                draft(threePoints, route: RouteFixtures.route, activityType: .cycling),
                draft([point(0, order: 0), point(2, order: 1)], activityType: .cycling)
            ]
        )
    }

    func test_failingSave_isLoggedAndPlanningGoesOn() async {
        let store = FakeRouteDraftStore()
        store.setSaveFailing(true)
        let logger = FakeLogger()
        let viewModel = makeSubject(store: store, logger: logger)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        await waitUntil { viewModel.startPoint != nil }

        viewModel.onMapTapped(RouteFixtures.waypoint(0))
        await waitUntil { logger.messages.count == 1 }
        viewModel.onMapTapped(RouteFixtures.waypoint(1))
        await waitUntil { logger.messages.count == 2 }

        XCTAssertEqual(viewModel.waypoints, [point(0, order: 0), point(1, order: 1)])
        XCTAssertTrue(recorder.events.isEmpty)
    }

    // MARK: - Clear

    func test_reset_clearsStoredPlanAndKeepsOnlyTheNewStartPoint() async {
        let store = FakeRouteDraftStore(stored: Self.storedPlan)
        let viewModel = makeSubject(store: store)
        await waitUntil { viewModel.waypoints.count == 3 }

        viewModel.onResetClicked()

        // Reset's empty plan (a clear) and the new start point that follows are written latest-wins, so the
        // clear may be replaced before it runs; the stored plan is gone either way.
        let startOnly = draft([])
        await waitUntil { store.storedDraft == startOnly }
        XCTAssertFalse(store.savedDrafts.contains(Self.storedPlan))
    }

    func test_startTracking_clearsStoredPlanAndKeepsPlanOnScreen() async {
        let store = FakeRouteDraftStore(stored: Self.storedPlan)
        let viewModel = makeSubject(
            store: store,
            userProfileRepository: FakeUserProfileRepository(profile: UserProfile(weightKg: 70))
        )
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        await waitUntil { viewModel.generatedRoute != nil && viewModel.userProfile != nil }

        viewModel.onStartTrackingClicked()

        await waitUntil { store.clearCount == 1 }
        XCTAssertNil(store.storedDraft)
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(viewModel.waypoints, Self.storedPlan.waypoints)
        XCTAssertEqual(viewModel.generatedRoute, RouteFixtures.route)
    }

    func test_startTrackingThatAsksForTheProfile_keepsStoredPlan() async {
        let store = FakeRouteDraftStore(stored: Self.storedPlan)
        let viewModel = makeSubject(store: store)
        let recorder = EventRecorder(viewModel.makeEventsStream())
        defer { recorder.stop() }
        await waitUntil { viewModel.generatedRoute != nil }

        viewModel.onStartTrackingClicked()

        await waitUntil { !recorder.events.isEmpty }
        guard case .requestUserProfile = recorder.events.first else {
            return XCTFail("expected requestUserProfile, got \(recorder.events)")
        }
        XCTAssertEqual(store.clearCount, 0)
        XCTAssertEqual(store.storedDraft, Self.storedPlan)
    }
}
