//
//  UITestProbe.swift
//  TrailMetricsUITests
//

import XCTest

/// The refresh generation, the four counters and the Route map's waypoint count (-1: not found)
/// the app's probe overlay shows in UI-test mode, as
/// `refreshes=<n> directions=<n> directionsDone=<n> saves=<n> deletes=<n> waypoints=<n>`.
struct ProbeCounters {
    let refreshes: Int
    let directions: Int
    let directionsDone: Int
    let saves: Int
    let deletes: Int
    let waypoints: Int

    /// Nil unless `label` has exactly the probe's six `key=<n>` pairs.
    init?(label: String) {
        var values: [String: Int] = [:]
        for pair in label.split(separator: " ") {
            let parts = pair.split(separator: "=")
            guard parts.count == 2, let value = Int(parts[1]) else { return nil }
            values[String(parts[0])] = value
        }
        guard values.count == 6,
              let refreshes = values["refreshes"],
              let directions = values["directions"],
              let directionsDone = values["directionsDone"],
              let saves = values["saves"],
              let deletes = values["deletes"],
              let waypoints = values["waypoints"] else { return nil }
        self.refreshes = refreshes
        self.directions = directions
        self.directionsDone = directionsDone
        self.saves = saves
        self.deletes = deletes
        self.waypoints = waypoints
    }
}

/// Reads the app's probe overlay (`uitest.probe`). The app reads the counters only when the
/// probe's refresh button is tapped, and the text carries a refresh generation (`refreshes=<n>`),
/// so a read is proven fresh: it returns only a text whose generation is higher than the one
/// shown before this read tapped, that is, a text written by a refresh this read triggered or a
/// later one. A slow runner can make a read time out; it cannot make it return an older text.
@MainActor
struct UITestProbe {
    let app: XCUIApplication

    /// Taps `uitest.probe.refresh` and returns the counters of a refresh that ran after the tap.
    func refreshedCounters() throws -> ProbeCounters {
        let refreshButton = app.buttons["uitest.probe.refresh"]
        let probe = app.staticTexts["uitest.probe"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 10), "Probe refresh button not found")
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "Probe text not found")
        // Before the first refresh the text has no generation: that is generation 0.
        let seen = ProbeCounters(label: probe.label)?.refreshes ?? 0

        // A refresh only reads counters, so a second tap (after a tap that seems lost) is harmless.
        for _ in 0..<2 {
            refreshButton.tap()
            let refreshed = NSPredicate { _, _ in
                (ProbeCounters(label: probe.label)?.refreshes ?? 0) > seen
            }
            let expectation = XCTNSPredicateExpectation(predicate: refreshed, object: nil)
            if XCTWaiter().wait(for: [expectation], timeout: 10) == .completed {
                return try XCTUnwrap(
                    ProbeCounters(label: probe.label), "Unexpected probe text: \(probe.label)"
                )
            }
        }
        XCTFail("Probe did not refresh within 10 s (still \(probe.label))")
        throw ProbeError.notRefreshed
    }
}

enum ProbeError: Error {
    case notRefreshed
}
