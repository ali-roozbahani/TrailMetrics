#if UITEST_SEAM
//
//  UITestProbeView.swift
//  TrailMetrics
//

import SharedKit
import SwiftUI

// UI-TEST SUPPORT ONLY. Compiled only in the Debug-UITest build configuration (UITEST_SEAM).

/// The UI-test probe: a small overlay at the top centre that shows the fakes' call counters and
/// the Route map's waypoint count, so a test can check "one request" or "one deletion", which the
/// UI itself cannot tell apart from two identical calls, or how many waypoints a map press added.
/// The counters are read only on a tap of `uitest.probe.refresh`, never on a timer or when SwiftUI
/// re-creates the view, so nothing depends on timing; until the first tap the text says so. Every
/// refresh increments `refreshes`, which is the first pair of the text, so a test can tell a text
/// written by its own tap from an older one. `uitest.probe.release` only completes the held calls
/// and leaves the text alone. `uitest.probe.addWaypoint` adds the next Route waypoint through
/// `UITestWaypointSeam` and returns at once; it leaves the text, the generation and the counters
/// alone, so a test reads its result with a refresh. Only the three buttons take touches; the text
/// and the background let them through to the app underneath.
struct UITestProbeView: View {
    let controls: UiTestControls
    @State private var counters = "not read yet: tap Refresh"
    @State private var refreshCount = 0

    var body: some View {
        VStack(spacing: 2) {
            Text(counters)
                .font(.system(size: 9, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 160)
                .allowsHitTesting(false)
                .accessibilityIdentifier("uitest.probe")
            HStack(spacing: 8) {
                Button("Refresh") {
                    refreshCount += 1
                    counters = Self.describe(controls, refreshes: refreshCount)
                }
                .accessibilityIdentifier("uitest.probe.refresh")
                Button("Release") {
                    controls.releaseHeldCalls()
                }
                .accessibilityIdentifier("uitest.probe.release")
                Button("Add waypoint") {
                    UITestWaypointSeam.addNext()
                }
                .accessibilityIdentifier("uitest.probe.addWaypoint")
            }
            .font(.system(size: 10))
        }
        .padding(4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.regularMaterial)
                .allowsHitTesting(false)
        }
    }

    private static func describe(_ controls: UiTestControls, refreshes: Int) -> String {
        "refreshes=\(refreshes) directions=\(controls.directionsRequestCount) "
            + "directionsDone=\(controls.directionsCompletedCount) "
            + "saves=\(controls.saveCount) deletes=\(controls.deleteCount) "
            + "waypoints=\(UITestWaypointCount.current())"
    }
}
#endif
