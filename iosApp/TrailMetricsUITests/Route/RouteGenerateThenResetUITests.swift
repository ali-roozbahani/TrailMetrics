//
//  RouteGenerateThenResetUITests.swift
//  TrailMetricsUITests
//

import XCTest

// Scenario GenerateThenReset (docs/epics/ios-ui-tests.md): empty history, every directions request
// is held until the probe's release. Reset is tapped while the request is in flight; the screen
// must be clean (no route, Generate back to its text and disabled), also after the release.
// `directionsDone` is deliberately not asserted: the cancelled call is cancelled in Kotlin through
// SKIE and never counts as completed, which is a cancellation detail, not what the user sees.
final class RouteGenerateThenResetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_resetWhileGenerating_leavesACleanScreen() throws {
        let app = XCUIApplication.launched(scenario: "GenerateThenReset")
        app.addRouteWaypoints(count: 3)

        let generateButton = app.buttons["route.generateButton"]
        generateButton.tap()

        // Positive signal 1: the request reached the fake, so Reset cannot cancel it before that.
        // Bounded poll of probe refreshes (10 s overall, no sleep; each read waits for the probe).
        let probe = UITestProbe(app: app)
        var counters = try probe.refreshedCounters()
        let deadline = Date().addingTimeInterval(10)
        while counters.directions < 1, Date() < deadline {
            counters = try probe.refreshedCounters()
        }
        XCTAssertEqual(counters.directions, 1, "The directions request never reached the fake")

        let resetButton = app.buttons["route.resetButton"]
        XCTAssertTrue(resetButton.waitForExistence(timeout: 10), "Route reset button not found")
        resetButton.tap()

        // Positive signal 2: the Reset was processed, Generate shows its text again and is disabled.
        let isIdleAndDisabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@ AND isEnabled == false", "Generate Route"),
            object: generateButton
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [isIdleAndDisabled], timeout: 10),
            .completed,
            "Generate did not return to its disabled text state after the Reset"
        )

        _ = try probe.releasedCounters()
        counters = try probe.refreshedCounters()
        XCTAssertEqual(counters.directions, 1, "Neither the Reset nor the release may request directions again")

        // Absence only after the positive signals above.
        XCTAssertFalse(app.buttons["Start Tracking"].exists, "A route from before the Reset was shown")
        XCTAssertFalse(generateButton.isEnabled, "Generate must stay disabled: the Reset cleared the waypoints")
    }
}
