//
//  AccessibilityAuditUITests.swift
//  TrailMetricsUITests
//
//  Xcode's accessibility audit on the production screens: every element has a description a screen reader
//  can speak and every control a hit region large enough to touch. Two things are left out of the audit by
//  `isOutsideTheAudit`: the map (the Maps SDK's, not ours) and the UI-test probe overlay (test-only).
//

import XCTest

final class AccessibilityAuditUITests: XCTestCase {

    private static let auditedTypes: XCUIAccessibilityAuditType = [.sufficientElementDescription, .hitRegion]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func audit(_ app: XCUIApplication, screen: String) throws {
        var reported: [String] = []
        try app.performAccessibilityAudit(for: Self.auditedTypes) { issue in
            if !Self.isOutsideTheAudit(issue.element) {
                let element = issue.element
                let name = element.map { "\($0.elementType.rawValue) label '\($0.label)' id '\($0.identifier)'" } ?? "-"
                reported.append("type \(issue.auditType.rawValue): \(issue.compactDescription): \(name)")
            }
            return true
        }
        XCTAssertEqual(reported, [], "Accessibility issues on \(screen)")
    }

    private static func isOutsideTheAudit(_ element: XCUIElement?) -> Bool {
        guard let element else { return false }
        let mapPrefixes = ["route.map", "details.map", "tracking.map", "uitest.probe"]
        return element.elementType == .map || mapPrefixes.contains { element.identifier.hasPrefix($0) }
    }

    @MainActor
    func test_routeScreen_passesTheAccessibilityAudit() throws {
        let app = XCUIApplication.launched(scenario: "GenerateTwice")
        XCTAssertTrue(app.buttons["route.resetButton"].waitForExistence(timeout: 10), "Route screen not shown")

        try audit(app, screen: "Route")
    }

    @MainActor
    func test_historyAndDetailsScreens_passTheAccessibilityAudit() throws {
        let app = XCUIApplication.launched(scenario: "FailedDelete")
        let historyTab = app.tabBars.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 10), "History tab button not found")
        historyTab.tap()
        let row = app.buttons["history.activityRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Seeded activity row not found")
        try audit(app, screen: "History")

        row.tap()
        XCTAssertTrue(app.buttons["details.deleteButton"].waitForExistence(timeout: 10), "Details screen not shown")
        try audit(app, screen: "Details")
    }

    @MainActor
    func test_trackingScreen_passesTheAccessibilityAudit() throws {
        let app = XCUIApplication.launched(scenario: "RestoredPausedSession")
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 10), "Tracking screen not shown")

        try audit(app, screen: "Tracking")
    }
}
