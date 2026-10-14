//
//  TrackingFinishTwiceUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario FinishTwice (docs/epics/ios-ui-tests.md): empty history, every save is held until the
// probe's release, and the location updates walk the planned loop to its end once Start is tapped.
// Finish is tapped twice quickly while the first save is held; after the release the History tab
// must show exactly one activity and the fake must have saved once.
final class TrackingFinishTwiceUITests: XCTestCase {

    /// Probe reads after the first History row is shown. A second save would complete right after
    /// the first (both wait on the same gate), so a few reads taken after the row cover it without
    /// a sleep: each read is a tap and a wait on the app.
    private static let settleReadCount = 3

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_finishTwice_savesOneActivity() throws {
        let app = XCUIApplication.launched(scenario: "FinishTwice")
        app.addRouteWaypoints(count: 3)
        app.buttons["route.generateButton"].tap()

        let startTracking = app.buttons["Start Tracking"]
        XCTAssertTrue(startTracking.waitForExistence(timeout: 10), "Start Tracking not shown after Generate")
        startTracking.tap()

        let startButton = app.buttons["Start"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "Start button not shown on the Tracking screen")
        startButton.tap()

        // The walk reached the end of the loop: the completion card replaces the controls.
        let finishButton = app.buttons["Finish"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 10), "Finish not shown: the route was not completed")
        finishButton.doubleTap()

        let probe = UITestProbe(app: app)
        _ = try probe.releasedCounters()

        // Positive signal: the first save completed and Tracking was dismissed to the Route tab.
        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10), "History tab not shown after the save")
        historyTab.tap()

        let rows = app.descendants(matching: .any).matching(identifier: "history.activityRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "No history row after the release")

        var maxSaves = 0
        for _ in 0..<Self.settleReadCount {
            maxSaves = max(maxSaves, try probe.refreshedCounters().saves)
        }
        XCTAssertEqual(maxSaves, 1, "Two taps on Finish must save the activity once")
        XCTAssertEqual(rows.count, 1, "Two taps on Finish must leave one history row")
    }
}
