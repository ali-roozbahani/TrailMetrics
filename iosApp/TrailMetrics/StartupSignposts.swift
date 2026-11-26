//
//  StartupSignposts.swift
//  TrailMetrics
//

import os

/// Named intervals of the app's start (`os_signpost`), read by Instruments and by the launch measurement
/// `LaunchPerformanceTests` (docs/performance/). A signpost costs next to nothing while no tool records it.
/// The subsystem, category and interval names are repeated in `LaunchPerformanceTests`: change both together.
enum StartupSignposts {
    static let signposter = OSSignposter(subsystem: "dev.roozbahani.TrailMetrics", category: "Startup")

    private static let firstScreenName: StaticString = "FirstScreenAppear"
    private static var firstScreenInterval: OSSignpostIntervalState?

    /// Starts `FirstScreenAppear` at the end of `TrailMetricsApp.init`.
    static func beginFirstScreen() {
        firstScreenInterval = signposter.beginInterval(firstScreenName)
    }

    /// Ends `FirstScreenAppear` when the root view first appears; a later appearance does nothing.
    static func endFirstScreen() {
        guard let interval = firstScreenInterval else { return }
        signposter.endInterval(firstScreenName, interval)
        firstScreenInterval = nil
    }
}
