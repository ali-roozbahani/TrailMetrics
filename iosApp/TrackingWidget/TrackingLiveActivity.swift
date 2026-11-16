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
                    metricLabel(systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                        Text(formatDistance(meters: context.state.distanceMeters))
                            .opacity(context.isStale ? 0.5 : 1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    metricLabel(systemImage: "speedometer") {
                        Text(formatSpeed(metersPerSecond: currentSpeed(context)))
                            .opacity(context.isStale ? 0.5 : 1)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    metricLabel(systemImage: "timer") { ElapsedTimerText(state: context.state) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Link(destination: TrackingLiveActivityConstants.deepLinkURL) {
                            Label { Text("Open", bundle: .main) } icon: { Image(systemName: "arrow.up.forward.app") }
                        }
                        Spacer()
                        Button(intent: StopTrackingIntent()) {
                            Label { Text("Stop", bundle: .main) } icon: { Image(systemName: "stop.fill") }
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

    private func metricLabel<Value: View>(systemImage: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            value()
                .font(.headline)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TrackingLockScreenView: View {
    let context: ActivityViewContext<TrackingActivityAttributes>

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label {
                    Text(LocalizedStringKey(context.attributes.activityType), bundle: .main)
                } icon: {
                    Image(systemName: activitySymbolName(for: context.attributes.activityType))
                }
                .font(.headline)
                Spacer()
                Button(intent: StopTrackingIntent()) {
                    Label { Text("Stop", bundle: .main) } icon: { Image(systemName: "stop.fill") }
                }
                .tint(.red)
            }

            HStack(spacing: 16) {
                metric(
                    label: Text("Distance", bundle: .main),
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                ) {
                    Text(formatDistance(meters: context.state.distanceMeters))
                        .opacity(context.isStale ? 0.5 : 1)
                }
                metric(label: Text("Time", bundle: .main), systemImage: "timer") {
                    ElapsedTimerText(state: context.state)
                }
                metric(label: Text("Speed", bundle: .main), systemImage: "speedometer") {
                    Text(formatSpeed(metersPerSecond: currentSpeed(context)))
                        .opacity(context.isStale ? 0.5 : 1)
                }
            }
            if context.isStale {
                Text("Not updating", bundle: .main)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .widgetURL(TrackingLiveActivityConstants.deepLinkURL)
    }

    private func metric<Value: View>(
        label: Text,
        systemImage: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                label
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            value()
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The elapsed time, drawn by the system from the state's start date: it advances with no update and, once
/// the session is paused, is held at the date it was paused. The upper bound is longer than a Live Activity
/// can last (8 hours active, then up to 4 on the lock screen).
private struct ElapsedTimerText: View {
    let state: TrackingActivityAttributes.ContentState

    var body: some View {
        Text(
            timerInterval: state.timerStart...state.timerStart.addingTimeInterval(12 * 60 * 60),
            pauseTime: state.pausedAt,
            countsDown: false,
            showsHours: false
        )
        .multilineTextAlignment(.center)
    }
}

/// A stale speed is not shown: it is the speed of a moment the app has not updated since.
private func currentSpeed(_ context: ActivityViewContext<TrackingActivityAttributes>) -> Double? {
    context.isStale ? nil : context.state.currentSpeedMetersPerSecond
}

// Matches Route's StartTrackingPanel.swift (ActivityTypeControl.symbolName) —
// same activity types, same icons. Keyed by the display-name String from
// TrackingActivityAttributes.activityType (set from TrackingViewModel's own
// liveActivityTypeKey) rather than the Kotlin ActivityType enum itself,
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

private func formatSpeed(metersPerSecond: Double?) -> String {
    guard let metersPerSecond else { return "-- km/h" }
    return String(format: "%.1f km/h", metersPerSecond * 3.6)
}
