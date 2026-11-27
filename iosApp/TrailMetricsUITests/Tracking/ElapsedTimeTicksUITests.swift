//
//  ElapsedTimeTicksUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario RestoredPausedSession (docs/epics/ios-ui-tests.md): a Paused session of 400 m and 05:00 is offered at
// launch, and the scenario's fake location sends no fix at all. After Resume the session records with no location
// event, so a Time cell that moves past 05:00 shows the panel's own once-a-second tick (MetricsDisplay's
// TimelineView reading TrackingViewModel.displayedElapsedMillis), not a state change from a fix.
final class ElapsedTimeTicksUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_afterResume_theTimeCellMovesWithoutALocationEvent() {
        let app = XCUIApplication.launched(scenario: "RestoredPausedSession")
        let resumeButton = app.buttons["Resume"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 10), "The restored session was not offered: no Resume")
        XCTAssertTrue(metricCell(in: app, label: "Time", value: "05:00").exists, "The restored time is not shown")

        resumeButton.tap()

        // Any second after 05:00 within the wait: the panel re-reads the time once a second.
        let movedTime = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Time' AND label MATCHES '.*05:(0[1-9]|1[0-9]).*'"))
            .firstMatch
        XCTAssertTrue(movedTime.waitForExistence(timeout: 10), "The Time cell did not move past 05:00 after Resume")
        // No location event arrived: the distance is still the restored one.
        let restoredDistance = metricCell(in: app, label: "Distance", value: "400 m")
        XCTAssertTrue(restoredDistance.exists, "A location event moved the distance")
    }

    /// The metric cell is one accessibility element whose label combines its caption and its value.
    private func metricCell(in app: XCUIApplication, label: String, value: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", label, value))
            .firstMatch
    }
}
