//
//  RouteNoConnectionRetryUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario NoConnectionThenRoute: the first directions request fails with no connection, every later one
// returns the route. Generate shows the "No Connection" alert; its Retry generates again and the route is
// shown (the Start Tracking panel), with exactly two directions requests.
final class RouteNoConnectionRetryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_generateWithNoConnection_showsAlertAndRetryShowsRoute() throws {
        let app = XCUIApplication.launched(scenario: "NoConnectionThenRoute")
        try app.addRouteWaypoints(count: 3)

        app.buttons["route.generateButton"].tap()

        let alert = app.alerts["No Connection"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "No Connection alert not shown")
        let retryButton = alert.buttons["Retry"]
        XCTAssertTrue(retryButton.exists, "The No Connection alert has no Retry")
        retryButton.tap()

        // Positive signal first: the route arrived and the Start Tracking panel is shown.
        let startTracking = app.buttons["Start Tracking"]
        XCTAssertTrue(startTracking.waitForExistence(timeout: 10), "Start Tracking not shown after Retry")

        let counters = try UITestProbe(app: app).refreshedCounters()
        XCTAssertEqual(counters.directions, 2, "Retry must make exactly one more directions request")
        XCTAssertFalse(alert.exists, "The alert stayed after Retry")
    }
}
