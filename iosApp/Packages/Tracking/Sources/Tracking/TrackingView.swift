//
//  TrackingView.swift
//  Tracking
//

import SharedKit
import SwiftUI

public struct TrackingView: View {
    @StateObject private var viewModel: TrackingViewModel
    @Environment(\.dismiss) private var dismiss

    // This view never holds a raw GMSMapView — TrackingMapView is the sole owner
    // (SwiftUI's own UIViewRepresentable-hosting lifetime, plus the `mapView`
    // parameter its own updateUIView already receives). Finish requests a snapshot
    // by writing a new UUID here; TrackingMapView notices the change, takes the
    // snapshot itself, and reports the result back via `handleSnapshotReady`.
    @State private var snapshotRequestID: UUID?
    @State private var errorMessage: String?
    @State private var showExitConfirmation = false
    @State private var routeProgress: RouteProgress?
    @State private var lastProgressIndex: Int32 = 0
    @State private var hasReachedDestination = false

    private static let routeCompletionIndexMargin: Int32 = 3
    private static let routeCompletionThresholdMeters = 25.0

    public init(activityType: ActivityType, plannedRoutePoints: [Coordinates], startPoint: Coordinates) {
        _viewModel = StateObject(wrappedValue: TrackingViewModel(
            activityType: activityType,
            plannedRoutePoints: plannedRoutePoints,
            startPoint: startPoint
        ))
    }

    public var body: some View {
        ZStack {
            TrackingMapView(
                startPoint: viewModel.startPoint,
                plannedRoutePoints: viewModel.plannedRoutePoints,
                traveledSegment: routeProgress?.traveledSegment ?? [],
                currentLocation: viewModel.currentPath.last,
                snapshotRequestID: $snapshotRequestID,
                onSnapshotReady: handleSnapshotReady
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                VStack(spacing: 16) {
                    if let metrics = viewModel.currentMetrics {
                        MetricsDisplay(metrics: metrics, calories: viewModel.calories)
                    }

                    if hasReachedDestination {
                        finishCard
                    } else {
                        controlsRow
                    }
                }
                .padding()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if viewModel.canPause || viewModel.canResume {
                        showExitConfirmation = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .alert(Text("Stop tracking?", bundle: .module), isPresented: $showExitConfirmation) {
            Button(role: .destructive) {
                viewModel.onStopClicked()
                dismiss()
            } label: {
                Text("Stop & Exit", bundle: .module)
            }
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
        } message: {
            Text("Tracking is still in progress. Leaving now will stop and discard this activity.", bundle: .module)
        }
        .alert(
            Text("Error", bundle: .module),
            isPresented: Binding(get: { errorMessage != nil }, set: { isPresented in
                if !isPresented { errorMessage = nil }
            }),
            presenting: errorMessage
        ) { _ in
            Button { errorMessage = nil } label: { Text("OK", bundle: .module) }
        } message: { message in
            Text(message)
        }
        .onChange(of: viewModel.currentPath) { _, _ in
            updateRouteProgress()
        }
        .onChange(of: isRouteCompleted) { _, completed in
            if completed && !hasReachedDestination {
                hasReachedDestination = true
                viewModel.onStopClicked()
            }
        }
        .task {
            for await event in viewModel.makeEventsStream() {
                handle(event)
            }
        }
    }

    private func handle(_ event: TrackingUiEvent) {
        switch event {
        case .showError(let error):
            errorMessage = error.message
        case .dismissed:
            dismiss()
        }
    }

    private var isRouteCompleted: Bool {
        guard let currentLocation = viewModel.currentPath.last,
              !viewModel.plannedRoutePoints.isEmpty,
              case .tracking = onEnum(of: viewModel.trackingState),
              let progress = routeProgress,
              let lastPlannedPoint = viewModel.plannedRoutePoints.last
        else { return false }

        return progress.lastIndex >= Int32(viewModel.plannedRoutePoints.count) - Self.routeCompletionIndexMargin
            && currentLocation.distanceTo(to: lastPlannedPoint) <= Self.routeCompletionThresholdMeters
    }

    private func updateRouteProgress() {
        guard let currentLocation = viewModel.currentPath.last else { return }
        let result = calculateRouteProgress(
            plannedRoute: viewModel.plannedRoutePoints,
            currentLocation: currentLocation,
            previousIndex: lastProgressIndex,
            searchWindow: 10
        )
        lastProgressIndex = result.lastIndex
        routeProgress = result
    }

    private var controlsRow: some View {
        HStack(spacing: 12) {
            if viewModel.canStart {
                Button {
                    viewModel.onStartClicked()
                } label: {
                    Label { Text("Start", bundle: .module) } icon: { Image(systemName: "play.fill") }
                }
                .buttonStyle(.borderedProminent)
                .tint(.trailGreen)
            }
            if viewModel.canPause {
                Button {
                    viewModel.onPauseClicked()
                } label: {
                    Label { Text("Pause", bundle: .module) } icon: { Image(systemName: "pause.fill") }
                }
                .buttonStyle(.borderedProminent)
                .tint(.trailAmber)
            }
            if viewModel.canResume {
                Button {
                    viewModel.onResumeClicked()
                } label: {
                    Label { Text("Resume", bundle: .module) } icon: { Image(systemName: "play.fill") }
                }
                .buttonStyle(.borderedProminent)
                .tint(.trailGreen)
            }
            if viewModel.canStop {
                Button {
                    viewModel.onStopClicked()
                    dismiss()
                } label: {
                    Label { Text("Stop", bundle: .module) } icon: { Image(systemName: "stop.fill") }
                }
                .buttonStyle(.borderedProminent)
                .tint(.trailRed)
            }
        }
    }

    private var finishCard: some View {
        VStack(spacing: 12) {
            Text("Route completed!", bundle: .module)
                .font(.title3.weight(.semibold))
            Button {
                finishTracking()
            } label: {
                Label { Text("Finish", bundle: .module) } icon: { Image(systemName: "checkmark") }
            }
            .buttonStyle(.borderedProminent)
            .tint(.trailGreen)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func finishTracking() {
        // A request is pending until its path is delivered (the save runs off the main thread).
        guard snapshotRequestID == nil else { return }
        snapshotRequestID = UUID()
    }

    private func handleSnapshotReady(_ snapshotFilePath: String?) {
        viewModel.onFinishClicked(snapshotFilePath: snapshotFilePath) {
            dismiss()
        }
    }
}
