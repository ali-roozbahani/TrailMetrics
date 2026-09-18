//
//  DetailsView.swift
//  History
//

import SharedKit
import SwiftUI

public struct DetailsView: View {
    @StateObject private var viewModel: DetailsViewModel

    public init(activityId: Int64) {
        _viewModel = StateObject(wrappedValue: DetailsViewModel(activityId: activityId))
    }

    public var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let activity = viewModel.activity {
                DetailsContent(activity: activity)
            } else {
                Text("Activity Not Found")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DetailsContent: View {
    let activity: ActivityRecord

    var body: some View {
        VStack(spacing: 0) {
            DetailsMapView(
                plannedRoutePoints: activity.plannedRoutePoints,
                actualPath: activity.actualPath
            )
            .frame(height: 280)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    HistoryMetricCell(
                        label: "Distance",
                        value: formatDistance(meters: activity.distanceMeters),
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                    )
                    HistoryMetricCell(
                        label: "Duration",
                        value: formatElapsedTime(millis: activity.durationMillis),
                        systemImage: "timer"
                    )
                }
                HStack(spacing: 8) {
                    HistoryMetricCell(
                        label: "Avg. Speed",
                        value: formatSpeed(metersPerSecond: activity.averageSpeedMetersPerSecond),
                        systemImage: "speedometer"
                    )
                    HistoryMetricCell(
                        label: "Calories",
                        value: formatCalories(calories: activity.calories),
                        systemImage: "flame"
                    )
                }
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(12)

            Spacer()
        }
    }
}
