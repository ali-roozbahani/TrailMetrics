//
//  TrackingSessionNotSavedWithErrorUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario LocationIssueThenFailedSessionSave: right after Start the location is reported unavailable and the session's
// save fails, so a location error and the unsaved-session warning reach the Tracking screen together, while one of them
// is already on screen. The screen must show both, one after the other, through its one alert: the second alert comes
// after the first one's OK and is never lost (owner decision of 2026-11-25).
//
// Which of the two arrives first is not fixed (two observations of the view model deliver them), so the test accepts
// either order. The rule for an error already on screen (the warning waits behind it and comes next) is pinned by
// TrackingAlertQueueTests.
final class TrackingSessionNotSavedWithErrorUITests: XCTestCase {

    private let warningMessage = "Your recording may not be saved. Finish and save it before you close the app."
    private let errorMessage = "Unable to determine your current location."

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_errorAndWarningArrivingTogether_areBothShownOneAfterTheOther() throws {
        let app = XCUIApplication.launched(scenario: "LocationIssueThenFailedSessionSave")
        try app.addRouteWaypoints(count: 3)
        app.buttons["route.generateButton"].tap()

        let startTracking = app.buttons["Start Tracking"]
        XCTAssertTrue(startTracking.waitForExistence(timeout: 10), "Start Tracking not shown after Generate")
        startTracking.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Start button not shown on the Tracking screen")
        startButton.tap()

        // Two alerts, each confirmed with its OK, in either order.
        let firstMessage = try confirmAlert(in: app, ordinal: "first")
        let secondMessage = try confirmAlert(in: app, ordinal: "second")

        XCTAssertEqual(
            Set([firstMessage, secondMessage]),
            Set([errorMessage, warningMessage]),
            "Expected the location error and the unsaved-session warning, one after the other"
        )
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10), "Pause not shown: the session is not running")
        let counters = try UITestProbe(app: app).refreshedCounters()
        XCTAssertEqual(counters.warning, 0, "The warning is still raised after its OK")
    }

    /// Waits for an alert, returns which of the two known messages it shows, and taps its OK.
    @MainActor
    private func confirmAlert(in app: XCUIApplication, ordinal: String) throws -> String {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "No \(ordinal) alert: one of the two was lost")
        let message = try XCTUnwrap(
            [errorMessage, warningMessage].first { alert.staticTexts[$0].exists },
            "The \(ordinal) alert shows neither the location error nor the warning"
        )
        alert.buttons["OK"].tap()
        // The alert with this message is gone before the next one is looked for.
        let gone = NSPredicate(format: "exists == false")
        let shown = app.alerts.staticTexts[message]
        expectation(for: gone, evaluatedWith: shown)
        waitForExpectations(timeout: 10)
        return message
    }
}
