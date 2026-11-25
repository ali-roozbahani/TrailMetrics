//
//  RouteView.swift
//  Route
//

import DesignSystem
import GoogleMaps
import SharedKit
import SwiftUI

public struct RouteView: View {
    @StateObject private var viewModel = RouteViewModel()
    @State private var showProfileSheet = false
    @State private var errorMessage: String?
    @State private var showNoConnection = false
    @State private var mapView: GMSMapView?
    /// The zoom buttons' icon box grows with the user's text size.
    @ScaledMetric private var zoomIconSize: CGFloat = 20

    private let onNavigateToTracking: (Coordinates, [Coordinates], ActivityType) -> Void

    public init(onNavigateToTracking: @escaping (Coordinates, [Coordinates], ActivityType) -> Void) {
        self.onNavigateToTracking = onNavigateToTracking
    }

    public var body: some View {
        if RouteMapConfiguration.isMapAvailable {
            mapScreen
        } else {
            RouteMapUnavailableView()
        }
    }

    private var mapScreen: some View {
        ZStack {
            RouteMapView(
                startPoint: viewModel.startPoint,
                waypoints: viewModel.waypoints,
                generatedRoute: viewModel.generatedRoute,
                onMapTapped: viewModel.onMapTapped,
                onWaypointTapped: viewModel.onWaypointRemoved,
                mapView: $mapView
            )
            .ignoresSafeArea()
            .accessibilityIdentifier("route.map")

            if viewModel.startPoint == nil {
                ProgressView()
            }

            VStack {
                topBar
                Spacer()
                HStack {
                    Spacer()
                    zoomControls
                }
                bottomPanel
            }
            .padding()
        }
        .sheet(isPresented: $showProfileSheet) {
            UserProfileSheet(
                initialWeightKg: viewModel.userProfile?.weightKg,
                onSave: { weightKg in
                    viewModel.saveUserProfile(weightKg: weightKg)
                    showProfileSheet = false
                },
                onDismiss: { showProfileSheet = false }
            )
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
        .alert(Text("No Connection", bundle: .module), isPresented: $showNoConnection) {
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
            Button { viewModel.onGenerateRouteClicked() } label: { Text("Retry", bundle: .module) }
        } message: {
            Text("no_connection_message", bundle: .module)
        }
        .task {
            for await event in viewModel.makeEventsStream() {
                handle(event)
            }
        }
    }

    private func handle(_ event: RouteUiEvent) {
        switch event {
        case .showError(let error):
            errorMessage = error.message
        case .showNoConnection:
            showNoConnection = true
        case .requestUserProfile:
            showProfileSheet = true
        case .navigateToTracking(let startPoint, let plannedRoutePoints, let activityType):
            onNavigateToTracking(startPoint, plannedRoutePoints, activityType)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                showProfileSheet = true
            } label: {
                Image(systemName: "person.fill")
                    .foregroundStyle(Color.trailGreen)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel(Text("User Profile", bundle: .module))

            Spacer()

            Button {
                viewModel.onResetClicked()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.trailGreen)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel(Text("Reset", bundle: .module))
            .accessibilityIdentifier("route.resetButton")
        }
    }

    private var zoomControls: some View {
        VStack(spacing: 12) {
            Button {
                zoom(by: 1)
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Color.trailGreen)
                    .frame(width: zoomIconSize, height: zoomIconSize)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel(Text("Zoom in", bundle: .module))

            Button {
                zoom(by: -1)
            } label: {
                Image(systemName: "minus")
                    .foregroundStyle(Color.trailGreen)
                    .frame(width: zoomIconSize, height: zoomIconSize)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel(Text("Zoom out", bundle: .module))
        }
    }

    private func zoom(by delta: Float) {
        guard let mapView else { return }
        mapView.showZoom(mapView.camera.zoom + delta)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 12) {
            if viewModel.generatedRoute != nil, viewModel.startPoint != nil {
                StartTrackingPanel(
                    selectedActivityType: viewModel.selectedActivityType,
                    onActivityTypeSelected: viewModel.onActivityTypeSelected,
                    onResetClicked: viewModel.onResetClicked,
                    onStartTrackingClicked: viewModel.onStartTrackingClicked
                )
            }

            if viewModel.generatedRoute == nil {
                Button {
                    viewModel.onGenerateRouteClicked()
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Generate Route", bundle: .module)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.trailGreen)
                .disabled(!viewModel.canGenerateRoute)
                .accessibilityIdentifier("route.generateButton")
            }
        }
    }
}
