//
//  XCUIApplication+RouteMap.swift
//  TrailMetricsUITests
//

import XCTest

extension XCUIApplication {
    /// Normalized points of the long presses, all inside the map area: y 0.42 to 0.6 keeps clear of
    /// the probe overlay and the top-bar buttons (top), the zoom controls and the bottom panel
    /// (bottom), and x stays off the trailing edge where the zoom controls sit. Distinct points,
    /// none at the screen centre (the start marker). The app's `UITestWaypointSeam` has the same
    /// list in the same order.
    private static let waypointPoints: [CGVector] = [
        CGVector(dx: 0.25, dy: 0.42),
        CGVector(dx: 0.75, dy: 0.42),
        CGVector(dx: 0.5, dy: 0.6),
        CGVector(dx: 0.25, dy: 0.6),
        CGVector(dx: 0.7, dy: 0.55)
    ]

    /// Adds `count` Route waypoints through the probe's `uitest.probe.addWaypoint` button and waits
    /// until `route.generateButton` is enabled. The Route scenarios of S6 and S7 share it. The
    /// button makes the app call the map delegate's `didLongPressAt` (`UITestWaypointSeam`), so the
    /// coordinator, the view model and the markers run as for a press; only the Maps SDK's gesture
    /// recognition is skipped. The one test of the real press is `RouteMapLongPressUITests`.
    ///
    /// After each tap it waits (bounded, 10 s, no second tap) until the probe reports as many
    /// waypoints as taps were made. A tap that added none fails right there and names the step, the
    /// probe's count and the timings, with a screenshot and the timings attached; the final check
    /// of the Generate button stays as it was, for a button that does not enable although all
    /// waypoints exist. Timings of a passing run are printed (passing tests drop attachments under
    /// the project's default result-bundle settings).
    @MainActor
    func addRouteWaypoints(count: Int = 3) throws {
        XCTAssertLessThanOrEqual(count, Self.waypointPoints.count, "Not enough distinct map points")
        let map = descendants(matching: .any)["route.map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10), "Route map not found")
        let addButton = buttons["uitest.probe.addWaypoint"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Probe add-waypoint button not found")

        let probe = UITestProbe(app: self)
        let clock = ContinuousClock()
        let helperStart = clock.now
        var timings: [String] = []

        for index in 0..<count {
            let step = index + 1
            let tapStart = clock.now
            addButton.tap()
            let tapSeconds = Self.seconds(clock.now - tapStart)

            let reported = try Self.waypointCount(atLeast: step, probe: probe)
            let sinceStart = Self.seconds(clock.now - helperStart)
            timings.append(
                "waypoint \(step) of \(count): tap took \(tapSeconds) s, count \(reported), "
                    + "\(sinceStart) s since the helper began"
            )
            if reported < step {
                let message = "waypoint \(step) of \(count) was not added through the seam: count \(reported), "
                    + "expected \(step) (\(sinceStart) s since the helper began)"
                Self.attachFailureEvidence(
                    screenshot: screenshot(), timings: timings,
                    activity: "Route seam diagnostics", imageName: "route-map-at-lost-waypoint",
                    textName: "route-seam-timings"
                )
                XCTFail(message)
                return
            }
        }
        print("addRouteWaypoints timings: " + timings.joined(separator: "; "))
        try Self.expectGenerateEnabled(in: self, count: count)
    }

    /// Long-presses `route.map` `count` times (1 s each: a shorter press does not register, F6)
    /// and waits until `route.generateButton` is enabled. Only `RouteMapLongPressUITests` uses it:
    /// it is the real press path, with the Maps SDK's gesture recognition.
    ///
    /// After each press it waits (bounded, 10 s, no re-press) until the probe reports as many
    /// waypoints as presses were made. A press that added none fails right there and names the
    /// press, the probe's count and the timings, with a screenshot and the timings attached; the
    /// final check of the Generate button stays as it was (from three waypoints on), for a button
    /// that does not enable although all waypoints exist. Timings of a passing run are printed
    /// (passing tests drop attachments under the project's default result-bundle settings).
    @MainActor
    func pressRouteMapWaypoints(count: Int = 3) throws {
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

            let reported = try Self.waypointCount(atLeast: press, probe: probe)
            let sinceStart = Self.seconds(clock.now - helperStart)
            timings.append(
                "press \(press) of \(count): took \(pressSeconds) s, count \(reported), "
                    + "\(sinceStart) s since the helper began"
            )
            if reported < press {
                let message = "map press \(press) of \(count) did not add a waypoint: count \(reported), "
                    + "expected \(press) (press took \(pressSeconds) s, \(sinceStart) s since the helper began)"
                Self.attachFailureEvidence(
                    screenshot: screenshot(), timings: timings,
                    activity: "Route map press diagnostics", imageName: "route-map-at-lost-press",
                    textName: "route-map-press-timings"
                )
                XCTFail(message)
                return
            }
        }
        print("pressRouteMapWaypoints timings: " + timings.joined(separator: "; "))
        // Generate enables from three waypoints (the view model's minimum); fewer leave it disabled.
        if count >= 3 {
            try Self.expectGenerateEnabled(in: self, count: count)
        }
    }

    /// The same bounded poll as the Reset test: each read waits for a fresh probe text. Returns the
    /// last count read, which is below `expected` if 10 s passed without it reaching `expected`.
    @MainActor
    private static func waypointCount(atLeast expected: Int, probe: UITestProbe) throws -> Int {
        let deadline = Date().addingTimeInterval(10)
        var reported = try probe.refreshedCounters().waypoints
        while reported < expected, Date() < deadline {
            reported = try probe.refreshedCounters().waypoints
        }
        return reported
    }

    @MainActor
    private static func expectGenerateEnabled(in app: XCUIApplication, count: Int) throws {
        let generateButton = app.buttons["route.generateButton"]
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

    private static func attachFailureEvidence(
        screenshot: XCUIScreenshot, timings: [String], activity: String, imageName: String, textName: String
    ) {
        XCTContext.runActivity(named: activity) { activity in
            let image = XCTAttachment(screenshot: screenshot)
            image.name = imageName
            image.lifetime = .keepAlways
            activity.add(image)
            let text = XCTAttachment(string: timings.joined(separator: "\n"))
            text.name = textName
            text.lifetime = .keepAlways
            activity.add(text)
        }
    }
}
