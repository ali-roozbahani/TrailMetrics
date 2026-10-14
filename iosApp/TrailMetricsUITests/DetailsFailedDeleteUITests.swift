//
//  DetailsFailedDeleteUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario FailedDelete (docs/epics/ios-ui-tests.md): one seeded activity, every delete fails.
// Confirming the delete on the Details screen shows the "Error" alert with the general message,
// and after "OK" the Details screen is still there and nothing was deleted.
final class DetailsFailedDeleteUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_failedDelete_showsErrorAndKeepsDetails() throws {
        let app = XCUIApplication.launched(scenario: "FailedDelete")

        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10), "History tab button not found")
        historyTab.tap()

        let activityRow = app.buttons["history.activityRow"]
        XCTAssertTrue(activityRow.waitForExistence(timeout: 10), "Seeded activity row not found")
        activityRow.tap()

        let deleteButton = app.buttons["details.deleteButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10), "Details delete button not found")
        deleteButton.tap()

        let confirmation = app.alerts["Delete this activity?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10), "Delete confirmation not shown")
        confirmation.buttons["Delete"].tap()

        let errorAlert = app.alerts["Error"]
        XCTAssertTrue(errorAlert.waitForExistence(timeout: 10), "Error alert not shown")
        XCTAssertTrue(
            errorAlert.staticTexts["Something went wrong. Please try again."].exists,
            "Error alert does not show the general message"
        )
        errorAlert.buttons["OK"].tap()

        // Positive signal first: the probe answers a tap again, so no alert is covering the app.
        let counters = try UITestProbe(app: app).refreshedCounters()
        XCTAssertEqual(counters.deletes, 0, "A failed delete must not count as a deletion")
        XCTAssertFalse(errorAlert.exists, "Error alert still shown after OK")
        XCTAssertTrue(deleteButton.isHittable, "Details screen no longer shown after OK")
    }
}
