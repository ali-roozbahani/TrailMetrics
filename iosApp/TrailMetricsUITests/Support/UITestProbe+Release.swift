//
//  UITestProbe+Release.swift
//  TrailMetricsUITests
//

import XCTest

extension UITestProbe {
    /// Taps `uitest.probe.release` (completes every held call), then returns freshly refreshed
    /// counters; the calls finish asynchronously, so a count may not include them yet.
    func releasedCounters() throws -> ProbeCounters {
        let releaseButton = app.buttons["uitest.probe.release"]
        XCTAssertTrue(releaseButton.waitForExistence(timeout: 10), "Probe release button not found")
        releaseButton.tap()
        return try refreshedCounters()
    }
}
