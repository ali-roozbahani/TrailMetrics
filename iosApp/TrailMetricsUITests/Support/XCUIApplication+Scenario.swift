//
//  XCUIApplication+Scenario.swift
//  TrailMetricsUITests
//

import XCTest

extension XCUIApplication {
    /// Launches the app on the in-memory fakes of one scenario: `scenario` is the Kotlin `name`
    /// of a `UiTestScenario` entry (for example "FailedDelete"). The fakes start empty on every
    /// launch, so call this once per test (D5 of docs/epics/ios-ui-tests.md).
    @MainActor
    static func launched(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestScenario", scenario]
        app.launch()
        return app
    }
}
