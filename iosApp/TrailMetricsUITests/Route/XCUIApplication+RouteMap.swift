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
    ///
    /// After each press it waits (bounded, 10 s, no re-press) until the probe reports as many
    /// waypoints as presses were made. A press that added none fails right there and names the
    /// press, the probe's count and the timings, with a screenshot and the timings attached; the
    /// final check of the Generate button stays as it was, for a button that does not enable
    /// although all waypoints exist. Timings of a passing run are printed (passing tests drop
    /// attachments under the project's default result-bundle settings).
    @MainActor
    func addRouteWaypoints(count: Int = 3) throws {
        XCTAssertLessThanOrEqual(count, Self.waypointPoints.count, "Not enough distinct map points")
        let map = descendants(matching: .any)["route.map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10), "Route map not found")

        let probe = UITestProbe(app: self)
        let clock = ContinuousClock()
        let helperStart = clock.now
        var timings: [String] = []

        for (index, point) in Self.waypointPoints.prefix(count).enumerated() {
            let press = index + 1
            let pressStart = clock.now
            map.coordinate(withNormalizedOffset: point).press(forDuration: 1.0)
            let pressSeconds = Self.seconds(clock.now - pressStart)

            // The same bounded poll as the Reset test: each read waits for a fresh probe text.
            let deadline = Date().addingTimeInterval(10)
            var reported = try probe.refreshedCounters().waypoints
            while reported < press, Date() < deadline {
                reported = try probe.refreshedCounters().waypoints
            }
            let sinceStart = Self.seconds(clock.now - helperStart)
            timings.append(
                "press \(press) of \(count): took \(pressSeconds) s, count \(reported), "
                    + "\(sinceStart) s since the helper began"
            )
            if reported < press {
                let message = "map press \(press) of \(count) did not add a waypoint: count \(reported), "
                    + "expected \(press) (press took \(pressSeconds) s, \(sinceStart) s since the helper began)"
                Self.attachFailureEvidence(screenshot: screenshot(), timings: timings)
                XCTFail(message)
                return
            }
        }
        print("addRouteWaypoints timings: " + timings.joined(separator: "; "))

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

    private static func seconds(_ duration: Duration) -> String {
        let parts = duration.components
        let value = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        return String(format: "%.2f", value)
    }

    private static func attachFailureEvidence(screenshot: XCUIScreenshot, timings: [String]) {
        XCTContext.runActivity(named: "Route map press diagnostics") { activity in
            let image = XCTAttachment(screenshot: screenshot)
            image.name = "route-map-at-lost-press"
            image.lifetime = .keepAlways
            activity.add(image)
            let text = XCTAttachment(string: timings.joined(separator: "\n"))
            text.name = "route-map-press-timings"
            text.lifetime = .keepAlways
            activity.add(text)
        }
    }
}
