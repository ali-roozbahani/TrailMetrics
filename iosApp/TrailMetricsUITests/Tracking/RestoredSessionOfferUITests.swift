//
//  RestoredSessionOfferUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario RestoredPausedSession (docs/epics/ios-ui-tests.md): the session store holds a Paused session,
// as an app killed while paused leaves it. The app reads it at launch and offers it: the Tracking screen
// opens on its own with the restored session, which can be resumed or stopped but not started over.
final class RestoredSessionOfferUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_storedPausedSession_isOfferedAtLaunchAsTheTrackingScreen() {
        let app = XCUIApplication.launched(scenario: "RestoredPausedSession")

        let resumeButton = app.buttons["Resume"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 10), "The restored session was not offered: no Resume")

        // Positive signal first (Resume is shown), then the absences.
        XCTAssertTrue(app.buttons["Stop"].exists, "A restored Paused session can be stopped")
        XCTAssertFalse(app.buttons["Start"].exists, "A restored Paused session must not be started over")
        XCTAssertFalse(app.buttons["Pause"].exists, "A restored Paused session does not record by itself")
    }
}
