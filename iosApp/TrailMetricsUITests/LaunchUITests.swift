//
//  LaunchUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Launches the real app with no fakes: it passes no -uiTestScenario argument, so the app runs the
// normal composition root (doInitKoinIos). It passes with or without a Maps key: with an empty
// key the Route tab shows a message instead of the map (RouteMapConfiguration.isMapAvailable),
// and the tab bar is there either way. The test asks for no location, network or map content;
// the tab bar is checked by existence only, so a system location alert on top of it does not make
// the test fail.
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
