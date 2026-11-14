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
        // The error alert sits on this container, one view level above the
        // delete-confirmation alert on `content`, so the two `.alert` modifiers don't
        // compete on the same view.
        ZStack {
            content
        }
        .alert(
            Text("error_alert_title", bundle: .module),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in if !isPresented { viewModel.onErrorDismissed() } }
            ),
            presenting: viewModel.errorMessage
        ) { _ in
            Button { viewModel.onErrorDismissed() } label: { Text("ok_button", bundle: .module) }
        } message: { message in
            Text(message)
        }
    }

    private var content: some View {
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
                Text("Activity Not Found", bundle: .module)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        // No system nav bar here: Back and Delete are both custom circular buttons
        // floating on the map (matching Android's DetailsScreen and this app's own
        // Route topBar), not nav-bar chrome that would push the map down.
        .toolbar(.hidden, for: .navigationBar)
        .alert(Text("delete_activity_title", bundle: .module), isPresented: $showDeleteConfirmation) {
            Button(role: .destructive) {
                viewModel.onDeleteConfirmed {
                    dismiss()
                }
            } label: {
                Text("delete_button", bundle: .module)
            }
            Button(role: .cancel) {} label: { Text("cancel_button", bundle: .module) }
        } message: {
            Text("delete_activity_message", bundle: .module)
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
                        label: Text("metric_distance", bundle: .module),
                        value: formatDistance(meters: activity.distanceMeters),
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up"
                    )
                    HistoryMetricCell(
                        label: Text("metric_duration", bundle: .module),
                        value: formatElapsedTime(millis: activity.durationMillis),
                        systemImage: "timer"
                    )
                }
                HStack(spacing: 8) {
                    HistoryMetricCell(
                        label: Text("Avg. Speed", bundle: .module),
                        value: formatSpeed(metersPerSecond: activity.averageSpeedMetersPerSecond),
                        systemImage: "speedometer"
                    )
                    HistoryMetricCell(
                        label: Text("metric_calories", bundle: .module),
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
            .accessibilityIdentifier("details.deleteButton")
        }
    }
}
