//
//  DetailsDeleteTwiceUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario DeleteTwice (docs/epics/ios-ui-tests.md): one seeded activity, every delete is held
// until the probe's release. The delete is confirmed a second time while the first one is in
// flight; after the release exactly one delete completed and History shows no row.
final class DetailsDeleteTwiceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_deleteConfirmedTwice_deletesOnce() throws {
        let app = XCUIApplication.launched(scenario: "DeleteTwice")

        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10), "History tab button not found")
        historyTab.tap()

        let activityRow = app.buttons["history.activityRow"]
        XCTAssertTrue(activityRow.waitForExistence(timeout: 10), "Seeded activity row not found")
        activityRow.tap()

        // First confirmation: the delete is now held, the Details screen stays.
        confirmDelete(in: app, attempt: "first")
        // Second confirmation while the first delete is in flight.
        confirmDelete(in: app, attempt: "second")

        let probe = UITestProbe(app: app)
        _ = try probe.releasedCounters()

        // Positive signal first: the delete finished and the Details screen was left.
        let emptyState = app.staticTexts["No Activities yet"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 10), "History empty state not shown after the delete")
        XCTAssertFalse(activityRow.exists, "Deleted activity row still shown")

        let counters = try probe.refreshedCounters()
        XCTAssertEqual(counters.deletes, 1, "Two confirmations must delete the activity once")
    }

    @MainActor
    private func confirmDelete(in app: XCUIApplication, attempt: String) {
        let deleteButton = app.buttons["details.deleteButton"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 10), "Details delete button not found (\(attempt))")
        deleteButton.tap()

        let confirmation = app.alerts["Delete this activity?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10), "Delete confirmation not shown (\(attempt))")
        confirmation.buttons["Delete"].tap()
    }
}
