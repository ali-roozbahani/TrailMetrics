//
//  DetailsView.swift
//  History
//

import DesignSystem
import SharedKit
import SwiftUI

public struct DetailsView: View {
    @StateObject private var viewModel: DetailsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    public init(activityId: Int64) {
        _viewModel = StateObject(wrappedValue: DetailsViewModel(activityId: activityId))
    }

    public var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if let activity = viewModel.activity {
                DetailsContent(
                    activity: activity,
                    onBackClicked: { dismiss() },
                    onDeleteClicked: { showDeleteConfirmation = true }
                )
            } else {
                Text("Activity Not Found")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        // No system nav bar here: Back and Delete are both custom circular buttons
        // floating on the map (matching Android's DetailsScreen and this app's own
        // Route topBar), not nav-bar chrome that would push the map down.
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete this activity?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                viewModel.onDeleteConfirmed {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the activity and its route data. This cannot be undone.")
        }
    }
}

private struct DetailsContent: View {
    let activity: ActivityRecord
    let onBackClicked: () -> Void
    let onDeleteClicked: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                DetailsMapView(
                    plannedRoutePoints: activity.plannedRoutePoints,
                    actualPath: activity.actualPath
                )
                .frame(height: 280)

                topBar
                    .padding()
            }

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

    // Mirrors Route's `topBar` (RouteView.swift): an HStack of circular
    // .thinMaterial buttons with a Spacer between, so Back and Delete share one
    // padding value and land in the same row by construction.
    private var topBar: some View {
        HStack {
            Button(action: onBackClicked) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(Color.black)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }

            Spacer()

            Button(action: onDeleteClicked) {
                Image(systemName: "trash")
                    .foregroundStyle(Color.trailRed)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
        }
    }
}
