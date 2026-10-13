//
//  LaunchUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Launches the real app with no fakes: there is no launch-time fake seam yet, so this needs the
// Maps key configuration that the machine building the app already has (the app does not start
// without it). The test asks for no location, network or map content; the tab bar is checked by
// existence only, so a system location alert on top of it does not make the test fail.
final class LaunchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_launch_showsRouteAndHistoryTabs() {
        let app = XCUIApplication()
        app.launch()

        let routeTab = app.tabBars.buttons["Route"]
        let historyTab = app.tabBars.buttons["History"]

        XCTAssertTrue(routeTab.waitForExistence(timeout: 10), "Route tab button not found after launch")
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10), "History tab button not found after launch")
    }
}
