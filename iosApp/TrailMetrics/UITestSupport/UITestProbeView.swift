#if UITEST_SEAM
//
//  UITestProbeView.swift
//  TrailMetrics
//

import SharedKit
import SwiftUI

// UI-TEST SUPPORT ONLY. Compiled only in the Debug-UITest build configuration (UITEST_SEAM).

/// The UI-test probe: a small overlay at the top centre that shows the fakes' call counters, so
/// a test can check "one request" or "one deletion", which the UI itself cannot tell apart from
/// two identical calls. The counters are read only on a tap of `uitest.probe.refresh` or
/// `uitest.probe.release`, never on a timer or when SwiftUI re-creates the view, so nothing
/// depends on timing; until the first tap the text says so. Only the two buttons take touches;
/// the text and the background let them through to the app underneath.
struct UITestProbeView: View {
    let controls: UiTestControls
    @State private var counters = "not read yet: tap Refresh"

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
                    counters = Self.describe(controls)
                }
                .accessibilityIdentifier("uitest.probe.refresh")
                Button("Release") {
                    controls.releaseHeldCalls()
                    counters = Self.describe(controls)
                }
                .accessibilityIdentifier("uitest.probe.release")
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

    private static func describe(_ controls: UiTestControls) -> String {
        "directions=\(controls.directionsRequestCount) directionsDone=\(controls.directionsCompletedCount) "
            + "saves=\(controls.saveCount) deletes=\(controls.deleteCount)"
    }
}
#endif
