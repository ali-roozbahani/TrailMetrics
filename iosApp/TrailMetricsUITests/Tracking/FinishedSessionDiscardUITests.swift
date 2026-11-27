//
//  FinishedSessionDiscardUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario FinishTwice (docs/epics/ios-ui-tests.md): the location updates walk the planned loop to its end once
// Start is tapped, so the finish card is shown. Its Discard asks first: Cancel keeps the finished session, and
// confirming leaves the screen Idle with Start offered and nothing saved.
final class FinishedSessionDiscardUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_discardOnTheFinishCard_asksFirstThenLeavesIdleWithoutSaving() throws {
        let app = XCUIApplication.launched(scenario: "FinishTwice")
        try app.addRouteWaypoints(count: 3)
        app.buttons["route.generateButton"].tap()

        let startTracking = app.buttons["Start Tracking"]
        XCTAssertTrue(startTracking.waitForExistence(timeout: 10), "Start Tracking not shown after Generate")
        startTracking.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Start button not shown on the Tracking screen")
        startButton.tap()

        let finishButton = app.buttons["Finish"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 10), "Finish not shown: the route was not completed")
        let discardButton = app.buttons["Discard"]
        XCTAssertTrue(discardButton.exists, "The finish card offers no Discard beside Finish")

        discardButton.tap()
        let confirmation = app.alerts["Discard this recording?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10), "Discard did not ask for a confirmation")
        XCTAssertTrue(
            confirmation.staticTexts["The recording will be deleted and cannot be recovered."].exists,
            "The confirmation does not say that the recording is deleted"
        )
        confirmation.buttons["Cancel"].tap()

        // Positive signal: the alert is gone; the finished session is still offered.
        XCTAssertTrue(finishButton.waitForExistence(timeout: 10), "Cancel did not keep the finished session")
        XCTAssertFalse(confirmation.exists, "The confirmation is still shown after Cancel")

        discardButton.tap()
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10), "Discard did not ask for a confirmation again")
        confirmation.buttons["Discard"].tap()

        // Positive signal: Start is offered again; then the finish card is gone and nothing was saved.
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Start not offered after the discard")
        XCTAssertFalse(finishButton.exists, "The finish card is still shown after the discard")
        XCTAssertEqual(try UITestProbe(app: app).refreshedCounters().saves, 0, "The discarded session was saved")
    }
}
