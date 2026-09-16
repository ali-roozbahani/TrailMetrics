//
//  TrackingLiveActivity.swift
//  TrackingWidgetExtension
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct TrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackingActivityAttributes.self) { context in
            TrackingLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    metricLabel(
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                        value: formatDistance(meters: context.state.distanceMeters)
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    metricLabel(
                        systemImage: "speedometer",
                        value: formatSpeed(metersPerSecond: context.state.currentSpeedMetersPerSecond)
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    metricLabel(systemImage: "timer", value: formatElapsed(millis: context.state.elapsedMillis))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Link(destination: TrackingLiveActivityConstants.deepLinkURL) {
                            Label("Open", systemImage: "arrow.up.forward.app")
                        }
                        Spacer()
                        Button(intent: StopTrackingIntent()) {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .tint(.red)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: activitySymbolName(for: context.attributes.activityType))
            } compactTrailing: {
                Text(formatDistance(meters: context.state.distanceMeters))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: activitySymbolName(for: context.attributes.activityType))
            }
            .widgetURL(TrackingLiveActivityConstants.deepLinkURL)
        }
    }

    private func metricLabel(systemImage: String, value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
    }
}

private struct TrackingLockScreenView: View {
    let context: ActivityViewContext<TrackingActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label(
                    context.attributes.activityType,
                    systemImage: activitySymbolName(for: context.attributes.activityType)
                )
                .font(.headline)
                Spacer()
                Button(intent: StopTrackingIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .tint(.red)
            }

            HStack(spacing: 16) {
                metric(
                    label: "Distance",
                    value: formatDistance(meters: context.state.distanceMeters),
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                )
                metric(
                    label: "Time",
                    value: formatElapsed(millis: context.state.elapsedMillis),
                    systemImage: "timer"
                )
                metric(
                    label: "Speed",
                    value: formatSpeed(metersPerSecond: context.state.currentSpeedMetersPerSecond),
                    systemImage: "speedometer"
                )
            }
        }
        .padding()
        .widgetURL(TrackingLiveActivityConstants.deepLinkURL)
    }

    private func metric(label: String, value: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// Matches Route's StartTrackingPanel.swift (ActivityTypeControl.symbolName) —
// same activity types, same icons. Keyed by the display-name String from
// TrackingActivityAttributes.activityType (set from TrackingViewModel's own
// activityTypeDisplayName) rather than the Kotlin ActivityType enum itself,
// since this target can't import SharedKit. Keep in sync with that mapping.
private func activitySymbolName(for activityType: String) -> String {
    switch activityType {
    case "Cycling": return "bicycle"
    case "Walking": return "figure.walk"
    default: return "figure.run"
    }
}

// Plain-Swift equivalents of domain/src/commonMain/.../util/MetricsFormatter.kt,
// kept visually consistent with MetricsDisplay.swift (same units/thresholds/
// decimal places). Not shared with that Kotlin file directly: this target
// must not link SharedKit, and Foundation's String(format:) is fine to use
// here since it's plain Swift (the Kotlin-side manual formatter exists only
// because kotlin-stdlib-common has no String.format equivalent).
private func formatDistance(meters: Double) -> String {
    if meters >= 1000 {
        return String(format: "%.2f km", meters / 1000)
    }
    return "\(Int(meters)) m"
}

private func formatElapsed(millis: Int64) -> String {
    let totalSeconds = millis / 1000
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
}

private func formatSpeed(metersPerSecond: Double?) -> String {
    guard let metersPerSecond else { return "-- km/h" }
    return String(format: "%.1f km/h", metersPerSecond * 3.6)
}
