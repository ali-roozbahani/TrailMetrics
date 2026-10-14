//
//  RouteGenerateTwiceUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario GenerateTwice (docs/epics/ios-ui-tests.md): empty history, every directions request is
// held until the probe's release. Generate is tapped twice quickly; after the release the route is
// shown and exactly one directions request was made.
final class RouteGenerateTwiceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_generateTwice_requestsDirectionsOnce() throws {
        let app = XCUIApplication.launched(scenario: "GenerateTwice")
        app.addRouteWaypoints(count: 3)

        let generateButton = app.buttons["route.generateButton"]
        generateButton.doubleTap()

        let probe = UITestProbe(app: app)
        _ = try probe.releasedCounters()

        // Positive signal first: the route arrived and the Start Tracking panel is shown.
        let startTracking = app.buttons["Start Tracking"]
        XCTAssertTrue(startTracking.waitForExistence(timeout: 10), "Start Tracking not shown after the release")

        let counters = try probe.refreshedCounters()
        XCTAssertEqual(counters.directions, 1, "Two taps on Generate must request directions once")
    }
}
