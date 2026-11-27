//
//  MetricsDisplay.swift
//  Tracking
//

import SharedKit
import SwiftUI

struct MetricsDisplay: View {
    let metrics: TrackingMetrics
    /// The ticking time of the screen (`TrackingViewModel.elapsedTime`), not `metrics.elapsedMillis`; observed
    /// here only, so a tick re-renders this panel and not the screen around it.
    @ObservedObject var elapsedTime: ElapsedTimeTicker
    let calories: Double?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TrackingMetricCell(
                    label: Text("Distance", bundle: .module),
                    value: formatDistance(meters: metrics.distanceMeters),
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                )
                TrackingMetricCell(
                    label: Text("Time", bundle: .module),
                    value: formatElapsedTime(millis: elapsedTime.displayedElapsedMillis),
                    systemImage: "timer"
                )
            }
            HStack(spacing: 8) {
                TrackingMetricCell(
                    label: Text("Speed", bundle: .module),
                    value: formatSpeed(metersPerSecond: metrics.currentSpeedMetersPerSecond),
                    systemImage: "speedometer"
                )
                TrackingMetricCell(
                    label: Text("Calories", bundle: .module),
                    value: formatCalories(calories: calories.map { KotlinDouble(double: $0) }),
                    systemImage: "flame"
                )
            }
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct TrackingMetricCell: View {
    let label: Text
    let value: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                label
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}
