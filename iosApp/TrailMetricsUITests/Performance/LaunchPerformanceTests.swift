//
//  LaunchPerformanceTests.swift
//  TrailMetricsUITests
//

import XCTest

// Measures the app's cold start for docs/performance/ (metric `cold_start_first_frame_ms`): XCTest's launch
// metric, from the launch to the app's first frame, and the app's own startup intervals (`StartupSignposts`).
// Like `LaunchUITests` it launches the real app with no scenario. It asserts no timing and has no Xcode
// baseline, so a slow run never fails it: the numbers are read from the result bundle and recorded by hand
// (docs/performance/ says how). The gate's UI run measures with XCTest's default iteration count; a
// measurement for the doc sets more through the runner's environment: `TEST_RUNNER_TM_LAUNCH_ITERATIONS=<n>`
// in the environment of xcodebuild (docs/performance/ios-cold-start.md has the command).
final class LaunchPerformanceTests: XCTestCase {

    // Must match `StartupSignposts` in the app target.
    private static let subsystem = "dev.roozbahani.TrailMetrics"
    private static let category = "Startup"
    private static let intervals = ["CrashReportingStart", "KoinStart", "MapsConfigure", "FirstScreenAppear"]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_coldLaunch_measuresFirstFrameAndStartupIntervals() {
        let signpostMetrics: [XCTMetric] = Self.intervals.map {
            XCTOSSignpostMetric(subsystem: Self.subsystem, category: Self.category, name: $0)
        }
        let options = XCTMeasureOptions()
        // Absent: XCTest's default. Present but not a positive number: a failure, so a measurement for the
        // doc is never taken with another count than the one asked for.
        if let value = ProcessInfo.processInfo.environment["TM_LAUNCH_ITERATIONS"] {
            guard let iterations = Int(value), iterations > 0 else {
                XCTFail("TM_LAUNCH_ITERATIONS must be a positive number, got '\(value)'")
                return
            }
            options.iterationCount = iterations
        }

        measure(metrics: [XCTApplicationLaunchMetric()] + signpostMetrics, options: options) {
            XCUIApplication().launch()
        }
    }
}
