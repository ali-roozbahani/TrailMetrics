//
//  LaunchUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Launches the real app with no fakes: it passes no -uiTestScenario argument, so the app runs the
// normal composition root (doInitKoinIos), and this needs the Maps key configuration that the
// machine building the app already has. With an empty key the app crashes as soon as the Route
// tab appears (the map view raises in the Maps SDK's precondition check; board record maps-empty-api-key-crashes-route-tab), so this test cannot pass without a
// key; the CI placeholder key is enough. The test asks for no location, network or map content;
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
