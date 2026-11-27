//
//  TrackingView.swift
//  Tracking
//

import SharedKit
import SwiftUI

public struct TrackingView: View {
    @StateObject private var viewModel: TrackingViewModel
    /// The one source of "the app is still reading the stored session". The view observes it so that
    /// Start (`viewModel.canStart`) is re-read when the read ends; the view model reads it too.
    @ObservedObject private var savedSessionOffer: SavedSessionOfferModel
    @Environment(\.dismiss) private var dismiss

    // This view never holds a raw GMSMapView — TrackingMapView is the sole owner
    // (SwiftUI's own UIViewRepresentable-hosting lifetime, plus the `mapView`
    // parameter its own updateUIView already receives). Finish requests a snapshot
    // by writing a new UUID here; TrackingMapView notices the change, takes the
    // snapshot itself, and reports the result back via `handleSnapshotReady`.
    @State private var snapshotRequestID: UUID?
    /// The errors and the unsaved-session warning, shown one after the other through the one error alert below
    /// (see TrackingAlertQueue). The warning's OK marks it shown.
    @State private var alerts = TrackingAlertQueue()
    @State private var showExitConfirmation = false

    public init(
        activityType: ActivityType,
        plannedRoutePoints: [Coordinates],
        startPoint: Coordinates,
        savedSessionOffer: SavedSessionOfferModel
    ) {
        self.savedSessionOffer = savedSessionOffer
        _viewModel = StateObject(wrappedValue: TrackingViewModel(
            activityType: activityType,
            plannedRoutePoints: plannedRoutePoints,
            startPoint: startPoint,
            storedSessionReadState: savedSessionOffer
        ))
    }

    public var body: some View {
        ZStack {
            TrackingMapView(
                startPoint: viewModel.startPoint,
                plannedRoutePoints: viewModel.plannedRoutePoints,
                traveledSegment: viewModel.routeProgress?.traveledSegment ?? [],
                recordedPath: viewModel.recordedPath,
                currentLocation: viewModel.recordedPath.last,
                snapshotRequestID: $snapshotRequestID,
                onSnapshotReady: handleSnapshotReady
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                VStack(spacing: 16) {
                    if let metrics = viewModel.currentMetrics {
                        MetricsDisplay(
                            metrics: metrics,
                            elapsedMillis: { viewModel.displayedElapsedMillis },
                            calories: viewModel.calories
                        )
                    }

                    if viewModel.canFinish {
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
                    if viewModel.canStop {
                        showExitConfirmation = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(Text("Back", bundle: .module))
            }
        }
        .alert(Text("Stop tracking?", bundle: .module), isPresented: $showExitConfirmation) {
            Button(role: .destructive) {
                viewModel.onDiscardClicked()
                dismiss()
            } label: {
                Text("Stop & Exit", bundle: .module)
            }
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
        } message: {
            Text("Tracking is still in progress. Leaving now will stop and discard this activity.", bundle: .module)
        }
        // One alert for errors and the warning: SwiftUI may not present a second `.alert` while one is up. The OK
        // removes the alert on screen; the binding's setter does nothing, so one OK never removes two alerts.
        .alert(
            Text("Error", bundle: .module),
            isPresented: Binding(get: { alerts.current != nil }, set: { _ in }),
            presenting: alerts.current
        ) { alert in
            Button { dismissAlert(alert) } label: { Text("OK", bundle: .module) }
        } message: { alert in
            switch alert {
            case .error(let message):
                Text(message)
            case .sessionNotSaved:
                Text("session_not_saved_message", bundle: .module)
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
            alerts.enqueue(.error(error.message))
        case .sessionNotSaved:
            alerts.enqueue(.sessionNotSaved)
        case .dismissed:
            dismiss()
        }
    }

    private func dismissAlert(_ alert: TrackingAlert) {
        guard alerts.dismiss(alert) else { return }
        if alert == .sessionNotSaved {
            viewModel.onSessionNotSavedShown()
        }
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
                    viewModel.onDiscardClicked()
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
