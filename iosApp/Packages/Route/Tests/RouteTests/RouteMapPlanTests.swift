//
//  RouteMapPlanTests.swift
//  RouteTests
//

@testable import Route
import SharedKit
import XCTest

final class RouteMapPlanTests: XCTestCase {

    private func waypoints(_ count: Int) -> [RoutePoint] {
        (0..<count).map { RoutePoint(coordinates: RouteFixtures.waypoint($0), order: Int32($0)) }
    }

    func test_isPlanFitNeeded_onlyForFirstWaypointsArrivingTwoOrMoreAtATime() {
        XCTAssertFalse(isPlanFitNeeded(waypoints: [], planAlreadySeen: false), "no waypoints")
        XCTAssertFalse(isPlanFitNeeded(waypoints: waypoints(1), planAlreadySeen: false), "a tapped first waypoint")
        XCTAssertTrue(isPlanFitNeeded(waypoints: waypoints(2), planAlreadySeen: false), "a restored plan")
        XCTAssertTrue(isPlanFitNeeded(waypoints: waypoints(5), planAlreadySeen: false), "a restored plan")
        XCTAssertFalse(isPlanFitNeeded(waypoints: waypoints(5), planAlreadySeen: true), "after the first waypoints")
    }

    func test_planPoints_areTheStartPointThenTheWaypointsThenTheRoutePoints() {
        let points = planPoints(
            startPoint: RouteFixtures.startPoint,
            waypoints: waypoints(2),
            generatedRoute: RouteFixtures.route
        )

        XCTAssertEqual(
            points,
            [RouteFixtures.startPoint, RouteFixtures.waypoint(0), RouteFixtures.waypoint(1)]
                + RouteFixtures.route.points.map(\.coordinates)
        )
        XCTAssertEqual(planPoints(startPoint: nil, waypoints: [], generatedRoute: nil), [])
    }
}
