//
//  TrackingSessionNotSavedUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario FailedSessionSave: every save of the in-progress session throws. Starting a session saves it at once,
// so the Tracking screen must show that the recording may not be saved, once.
final class TrackingSessionNotSavedUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_failingSessionSave_showsThatTheRecordingMayNotBeSaved() throws {
        let app = XCUIApplication.launched(scenario: "FailedSessionSave")
        try app.addRouteWaypoints(count: 3)
        app.buttons["route.generateButton"].tap()

        let startTracking = app.buttons["Start Tracking"]
        XCTAssertTrue(startTracking.waitForExistence(timeout: 10), "Start Tracking not shown after Generate")
        startTracking.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Start button not shown on the Tracking screen")
        startButton.tap()

        let message = "Your recording may not be saved. Finish and save it before you close the app."
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "No alert after the failed save")
        XCTAssertTrue(alert.staticTexts[message].exists, "The alert does not say that the recording may not be saved")
        alert.buttons["OK"].tap()

        // Positive signal: the alert is gone and the session runs (Pause is offered).
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10), "Pause not shown: the session is not running")

        // OK marked the warning shown, so no later screen offers it again.
        let counters = try UITestProbe(app: app).refreshedCounters()
        XCTAssertEqual(counters.warning, 0, "The warning is still raised after OK: the next screen would show it again")
    }
}
