//
//  StartWaitsForRestoreUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario HeldSessionRead (docs/epics/ios-ui-tests.md): nothing is stored, and the session store's
// read is held until the probe's release, as a slow read at launch. While the app is still reading
// the stored session the Tracking screen must not offer Start (a Start now could be overwritten by
// the session that the read is about to return); once the read ends, Start is offered.
final class StartWaitsForRestoreUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_startIsNotOfferedWhileTheStoredSessionIsRead_andIsOfferedAfter() throws {
        let app = XCUIApplication.launched(scenario: "HeldSessionRead")
        try app.addRouteWaypoints(count: 3)
        app.buttons["route.generateButton"].tap()

        let startTracking = app.buttons["Start Tracking"]
        XCTAssertTrue(startTracking.waitForExistence(timeout: 10), "Start Tracking not shown after Generate")
        startTracking.tap()

        // Positive signal: the Route tab's button is gone, the Tracking screen is shown.
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: startTracking)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "The Tracking screen was not shown")

        // The read is still held: one probe read is a round trip to the app, so the screen has settled.
        _ = try UITestProbe(app: app).refreshedCounters()
        XCTAssertFalse(app.buttons["Start"].exists, "Start must not be offered while the stored session is read")

        _ = try UITestProbe(app: app).releasedCounters()
        XCTAssertTrue(app.buttons["Start"].waitForExistence(timeout: 10), "Start not offered after the read ended")
    }
}
