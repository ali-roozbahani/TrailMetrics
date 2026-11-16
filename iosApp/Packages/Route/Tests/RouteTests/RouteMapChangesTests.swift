//
//  RouteMapChangesTests.swift
//  RouteTests
//
//  What the route map redraws when its content changes: only what differs, never the whole map.
//

@testable import Route
import SharedKit
import XCTest

final class RouteMapChangesTests: XCTestCase {

    private func point(_ index: Int) -> RoutePoint {
        RoutePoint(coordinates: RouteFixtures.waypoint(index), order: Int32(index))
    }

    private func content(
        start: Coordinates? = RouteFixtures.startPoint,
        waypoints: [RoutePoint] = [],
        route: Route? = nil
    ) -> RouteMapContent {
        RouteMapContent(startPoint: start, waypoints: waypoints, generatedRoute: route)
    }

    func test_firstContent_addsEverythingAndRemovesNothing() {
        let changes = routeMapChanges(from: nil, to: content(waypoints: [point(0)], route: RouteFixtures.route))

        XCTAssertEqual(changes, RouteMapChanges(
            replacesStartMarker: true,
            removedWaypoints: [],
            addedWaypoints: [point(0)],
            replacesRouteLine: true
        ))
    }

    func test_sameContent_changesNothing() {
        let shown = content(waypoints: [point(0), point(1)], route: RouteFixtures.route)

        let changes = routeMapChanges(from: shown, to: shown)

        XCTAssertTrue(changes.isEmpty, "Nothing changed, nothing is redrawn: \(changes)")
    }

    func test_oneWaypointTapped_addsOnlyThatMarker() {
        let before = content(waypoints: [point(0)])
        let after = content(waypoints: [point(0), point(1)])

        let changes = routeMapChanges(from: before, to: after)

        XCTAssertEqual(changes, RouteMapChanges(
            replacesStartMarker: false,
            removedWaypoints: [],
            addedWaypoints: [point(1)],
            replacesRouteLine: false
        ))
    }

    func test_oneWaypointRemoved_removesOnlyThatMarker() {
        let before = content(waypoints: [point(0), point(1)])
        let after = content(waypoints: [point(0)])

        let changes = routeMapChanges(from: before, to: after)

        XCTAssertEqual(changes.removedWaypoints, [point(1)])
        XCTAssertEqual(changes.addedWaypoints, [])
        XCTAssertFalse(changes.replacesStartMarker)
    }

    func test_routeGenerated_replacesOnlyTheRouteLine() {
        let before = content(waypoints: [point(0)])
        let after = content(waypoints: [point(0)], route: RouteFixtures.route)

        let changes = routeMapChanges(from: before, to: after)

        XCTAssertEqual(changes, RouteMapChanges(
            replacesStartMarker: false,
            removedWaypoints: [],
            addedWaypoints: [],
            replacesRouteLine: true
        ))
    }

    func test_reset_removesEveryWaypointAndTheRouteLine() {
        let before = content(waypoints: [point(0), point(1)], route: RouteFixtures.route)
        let after = content(waypoints: [])

        let changes = routeMapChanges(from: before, to: after)

        XCTAssertEqual(changes.removedWaypoints, [point(0), point(1)])
        XCTAssertEqual(changes.addedWaypoints, [])
        XCTAssertTrue(changes.replacesRouteLine)
        XCTAssertFalse(changes.replacesStartMarker)
    }

    func test_startPointMoved_replacesOnlyTheStartMarker() {
        let before = content(start: RouteFixtures.startPoint, waypoints: [point(0)])
        let after = content(start: RouteFixtures.waypoint(9), waypoints: [point(0)])

        let changes = routeMapChanges(from: before, to: after)

        XCTAssertTrue(changes.replacesStartMarker)
        XCTAssertEqual(changes.removedWaypoints, [])
        XCTAssertEqual(changes.addedWaypoints, [])
        XCTAssertFalse(changes.replacesRouteLine)
    }
}
