#if UITEST_SEAM
//
//  UITestScenarioArgument.swift
//  TrailMetrics
//

import Foundation
import SharedKit

// UI-TEST SUPPORT ONLY. Compiled only in the Debug-UITest build configuration (UITEST_SEAM),
// which links the test-only variant of TrailMetricsShared (ADR-002, "Amendment").

/// The `-uiTestScenario <name>` launch argument a UI test passes to start the app on the
/// in-memory fakes of one `UiTestScenario`.
enum UITestScenarioArgument {
    /// The scenario whose Kotlin `name` equals the argument's value, or nil when the app was
    /// launched without the argument (the normal composition root then runs). An unknown name is
    /// a mistake in the test, so it stops the app instead of silently running the real one.
    static func scenario() -> UiTestScenario? {
        // `-<key> <value>` launch arguments land in UserDefaults' argument domain.
        guard let name = UserDefaults.standard.string(forKey: "uiTestScenario") else { return nil }
        guard let scenario = UiTestScenario.allCases.first(where: { $0.name == name }) else {
            preconditionFailure("Unknown UI test scenario: \(name)")
        }
        return scenario
    }
}
#endif
