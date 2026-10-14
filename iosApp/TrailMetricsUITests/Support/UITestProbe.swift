//
//  UITestProbe.swift
//  TrailMetricsUITests
//

import XCTest

/// The four counters the app's probe overlay shows in UI-test mode, as
/// `directions=<n> directionsDone=<n> saves=<n> deletes=<n>`.
struct ProbeCounters {
    let directions: Int
    let directionsDone: Int
    let saves: Int
    let deletes: Int

    /// Nil unless `label` has exactly the probe's four `key=<n>` pairs.
    init?(label: String) {
        var values: [String: Int] = [:]
        for pair in label.split(separator: " ") {
            let parts = pair.split(separator: "=")
            guard parts.count == 2, let value = Int(parts[1]) else { return nil }
            values[String(parts[0])] = value
        }
        guard values.count == 4,
              let directions = values["directions"],
              let directionsDone = values["directionsDone"],
              let saves = values["saves"],
              let deletes = values["deletes"] else { return nil }
        self.directions = directions
        self.directionsDone = directionsDone
        self.saves = saves
        self.deletes = deletes
    }
}

/// Reads the app's probe overlay (`uitest.probe`). The app reads the counters only when one of
/// the probe's buttons is tapped, so every read here taps first.
@MainActor
struct UITestProbe {
    let app: XCUIApplication

    /// Taps `uitest.probe.refresh` and returns the counters the probe then shows.
    func refreshedCounters() throws -> ProbeCounters {
        let refreshButton = app.buttons["uitest.probe.refresh"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 10), "Probe refresh button not found")
        refreshButton.tap()

        let probe = app.staticTexts["uitest.probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "Probe text not found")
        return try XCTUnwrap(ProbeCounters(label: probe.label), "Unexpected probe text: \(probe.label)")
    }
}
