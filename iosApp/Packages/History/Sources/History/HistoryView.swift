//
//  HistoryView.swift
//  History
//
//  Created by Ali Roozbahani on 09.09.26.
//

import DesignSystem
import SharedKit
import SwiftUI

public struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var activityPendingDelete: ActivityRecord?

    let onActivitySelected: (Int64) -> Void

    public init(onActivitySelected: @escaping (Int64) -> Void) {
        self.onActivitySelected = onActivitySelected
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
            } else if viewModel.isEmpty {
                Text("No Activities yet", bundle: .module)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.activities, id: \.id) { activity in
                            Button {
                                onActivitySelected(activity.id)
                            } label: {
                                ActivityRow(
                                    activity: activity,
                                    onDeleteClicked: { activityPendingDelete = activity }
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("history.activityRow")
                        }
                    }
                    .padding(16)
                }
            }
        }
        .task {
            await viewModel.observe()
        }
        .alert(
            Text("delete_activity_title", bundle: .module),
            isPresented: Binding(
                get: { activityPendingDelete != nil },
                set: { isPresented in if !isPresented { activityPendingDelete = nil } }
            )
        ) {
            Button(role: .destructive) {
                if let activity = activityPendingDelete {
                    viewModel.onDeleteActivity(activity)
                }
                activityPendingDelete = nil
            } label: {
                Text("delete_button", bundle: .module)
            }
            Button(role: .cancel) {} label: { Text("cancel_button", bundle: .module) }
        } message: {
            Text("delete_activity_message", bundle: .module)
        }
    }
}

private struct ActivityRow: View {
    let activity: ActivityRecord
    let onDeleteClicked: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                snapshot
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipped()

                activityTypeBadge
                    .padding(8)

                HStack(spacing: 6) {
                    dateBadge
                    deleteButton
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

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
                HistoryMetricCell(
                    label: Text("metric_calories", bundle: .module),
                    value: formatCalories(calories: activity.calories),
                    systemImage: "flame"
                )
            }
            .padding(8)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var snapshot: some View {
        if let url = snapshotURL {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                        // Disables Live Text/Image Analysis interaction on the map
                        // snapshot (it auto-attaches to images with recognizable text,
                        // like street labels, and was intercepting taps meant for this
                        // row's Button).
                        .allowsHitTesting(false)
                } else {
                    Color(.tertiarySystemBackground)
                }
            }
        } else {
            Color(.tertiarySystemBackground)
        }
    }

    // See `resolvedSnapshotURL(forStoredPath:)` (SnapshotFile.swift) for why this
    // re-resolves the filename against the current Application Support directory
    // rather than trusting the stored absolute path (which goes stale across
    // reinstalls, causing AsyncImage to fail with NSURLErrorFileDoesNotExist).
    private var snapshotURL: URL? {
        resolvedSnapshotURL(forStoredPath: activity.snapshotFilePath)
    }

    private var activityTypeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: activity.activityType.iconName)
                .foregroundStyle(Color.trailGreen)
            Text(activity.activityType.displayName)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var dateBadge: some View {
        Text(Self.dateFormatter.string(from: activity.startedAtDate))
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var deleteButton: some View {
        Button(action: onDeleteClicked) {
            Image(systemName: "trash")
                .font(.caption2)
                .foregroundStyle(Color.trailRed)
                .padding(6)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

extension ActivityRecord {
    var startedAtDate: Date {
        Date(timeIntervalSince1970: Double(startedAtEpochMillis) / 1000)
    }
}

extension ActivityType {
    var iconName: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "figure.outdoor.cycle"
        case .walking: return "figure.walk"
        }
    }

    var displayName: String {
        switch self {
        case .running: return String(localized: "Running", bundle: .module)
        case .cycling: return String(localized: "Cycling", bundle: .module)
        case .walking: return String(localized: "Walking", bundle: .module)
        }
    }
}
