//
//  StartupSignposts.swift
//  TrailMetrics
//

import os

/// Named intervals of the app's start (`os_signpost`), read by Instruments and by the launch measurement
/// `LaunchPerformanceTests` (docs/performance/). A signpost costs next to nothing while no tool records it.
/// The subsystem, category and interval names are repeated in `LaunchPerformanceTests`: change both together.
enum StartupSignposts {
    static let signposter = OSSignposter(subsystem: "dev.roozbahani.trailmetrics", category: "Startup")
}
