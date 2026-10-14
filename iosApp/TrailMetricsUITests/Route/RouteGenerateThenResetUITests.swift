//
//  RouteGenerateThenResetUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario GenerateThenReset (docs/epics/ios-ui-tests.md): empty history, every directions request
// is held until the probe's release. Reset is tapped while the request is in flight; the late
// result arrives after the release and must not show a route.
final class RouteGenerateThenResetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_resetWhileGenerating_ignoresTheLateRoute() throws {
        let app = XCUIApplication.launched(scenario: "GenerateThenReset")
        app.addRouteWaypoints(count: 3)

        app.buttons["route.generateButton"].tap()
        let resetButton = app.buttons["route.resetButton"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 10), "Route reset button not found")
        resetButton.tap()

        let probe = UITestProbe(app: app)
        var counters = try probe.releasedCounters()

        // Positive signal first: the held request completed, so the late result was delivered.
        // Bounded poll of probe refreshes (10 s overall, no sleep; each read waits for the probe).
        let deadline = Date().addingTimeInterval(10)
        while counters.directionsDone < 1, Date() < deadline {
            counters = try probe.refreshedCounters()
        }
        XCTAssertEqual(counters.directionsDone, 1, "The held directions request did not complete")

        XCTAssertFalse(app.buttons["Start Tracking"].exists, "A route from before the Reset was shown")
        let generateButton = app.buttons["route.generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10), "Generate button not found after the Reset")
        XCTAssertFalse(generateButton.isEnabled, "Generate must be disabled: the Reset cleared the waypoints")
    }
}
