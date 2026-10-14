//
//  UITestProbe+Release.swift
//  TrailMetricsUITests
//

import XCTest

extension UITestProbe {
    /// Taps `uitest.probe.release` (completes every held call), returns the counters; the calls finish asynchronously.
    func releasedCounters() throws -> ProbeCounters {
        let releaseButton = app.buttons["uitest.probe.release"]
        XCTAssertTrue(releaseButton.waitForExistence(timeout: 10), "Probe release button not found")
        releaseButton.tap()

        let probe = app.staticTexts["uitest.probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 10), "Probe text not found")
        return try XCTUnwrap(ProbeCounters(label: probe.label), "Unexpected probe text: \(probe.label)")
    }
}
