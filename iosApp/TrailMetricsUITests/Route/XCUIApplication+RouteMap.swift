//
//  XCUIApplication+RouteMap.swift
//  TrailMetricsUITests
//

import XCTest

extension XCUIApplication {
    /// Normalized points of the long presses, all inside the map area: y 0.42 to 0.6 keeps clear of
    /// the probe overlay and the top-bar buttons (top), the zoom controls and the bottom panel
    /// (bottom), and x stays off the trailing edge where the zoom controls sit. Distinct points,
    /// none at the screen centre (the start marker).
    private static let waypointPoints: [CGVector] = [
        CGVector(dx: 0.25, dy: 0.42),
        CGVector(dx: 0.75, dy: 0.42),
        CGVector(dx: 0.5, dy: 0.6),
        CGVector(dx: 0.25, dy: 0.6),
        CGVector(dx: 0.7, dy: 0.55)
    ]

    /// Long-presses `route.map` `count` times (1 s each: a shorter press does not register, F6)
    /// and waits until `route.generateButton` is enabled. The Route scenarios of S6 and S7 share it.
    @MainActor
    func addRouteWaypoints(count: Int = 3) {
        XCTAssertLessThanOrEqual(count, Self.waypointPoints.count, "Not enough distinct map points")
        let map = descendants(matching: .any)["route.map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10), "Route map not found")

        for point in Self.waypointPoints.prefix(count) {
            map.coordinate(withNormalizedOffset: point).press(forDuration: 1.0)
        }

        let generateButton = buttons["route.generateButton"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 10), "Generate button not found")
        let isEnabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"),
            object: generateButton
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [isEnabled], timeout: 10),
            .completed,
            "Generate button not enabled after \(count) waypoints"
        )
    }
}
