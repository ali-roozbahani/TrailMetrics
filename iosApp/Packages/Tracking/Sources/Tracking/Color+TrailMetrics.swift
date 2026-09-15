//
//  Color+TrailMetrics.swift
//  Tracking
//

import SwiftUI

private extension Double {
    init(hex8Bit value: Int) {
        self = Double(value) / 255
    }
}

// Not `public`: this module's own Views are the only consumers. Route's package declares
// an identical (but separately-scoped) extension for its own internal use; both stay
// non-public specifically so importing both packages together (as TrailMetrics/ContentView.swift
// does) never hits "ambiguous use of member" from two public extensions with the same name.
extension Color {
    // TrailMetrics brand colors, matching androidApp's Color.kt (light theme values).
    static let trailGreen = Color(
        red: Double(hex8Bit: 0x2E), green: Double(hex8Bit: 0x7D), blue: Double(hex8Bit: 0x32)
    )
    static let trailGreenLight = Color(
        red: Double(hex8Bit: 0x60), green: Double(hex8Bit: 0xAD), blue: Double(hex8Bit: 0x5E)
    )
    static let trailBlue = Color(
        red: Double(hex8Bit: 0x15), green: Double(hex8Bit: 0x65), blue: Double(hex8Bit: 0xC0)
    )
    static let trailBlueLight = Color(
        red: Double(hex8Bit: 0x5E), green: Double(hex8Bit: 0x92), blue: Double(hex8Bit: 0xF3)
    )
    static let trailRed = Color(
        red: Double(hex8Bit: 0xC6), green: Double(hex8Bit: 0x28), blue: Double(hex8Bit: 0x28)
    )
    static let trailAmber = Color(
        red: Double(hex8Bit: 0xF9), green: Double(hex8Bit: 0xA8), blue: Double(hex8Bit: 0x25)
    )
}
