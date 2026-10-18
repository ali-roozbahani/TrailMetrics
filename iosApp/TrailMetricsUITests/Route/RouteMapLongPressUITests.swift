//
//  RouteMapLongPressUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario GenerateTwice (docs/epics/ios-ui-tests.md), used only for its launch state: empty
// history and no held calls until Generate. This is the one test that adds a Route waypoint with a
// real long press on the map; the other Route tests add theirs through the probe's seam. A press
// the Maps SDK does not register fails with the press helper's message (no retry, D6).
final class RouteMapLongPressUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_longPress_addsAWaypoint() throws {
        let app = XCUIApplication.launched(scenario: "GenerateTwice")
        try app.pressRouteMapWaypoints(count: 1)

        let counters = try UITestProbe(app: app).refreshedCounters()
        XCTAssertEqual(counters.waypoints, 1, "One long press must add one waypoint")
        XCTAssertFalse(
            app.buttons["route.generateButton"].isEnabled,
            "Generate must stay disabled with fewer than three waypoints"
        )
    }
}
