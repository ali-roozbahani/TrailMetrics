//
//  RouteView.swift
//  Route
//

import GoogleMaps
import SharedKit
import SwiftUI

public struct RouteView: View {
    @StateObject private var viewModel = RouteViewModel()
    @State private var showProfileSheet = false
    @State private var errorMessage: String?
    @State private var mapView: GMSMapView?

    private let onNavigateToTracking: (Coordinates, [Coordinates], ActivityType) -> Void

    public init(onNavigateToTracking: @escaping (Coordinates, [Coordinates], ActivityType) -> Void) {
        self.onNavigateToTracking = onNavigateToTracking
    }

    public var body: some View {
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
            "Error",
            isPresented: Binding(get: { errorMessage != nil }, set: { isPresented in
                if !isPresented { errorMessage = nil }
            }),
            presenting: errorMessage
        ) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .task {
            for await event in viewModel.events {
                handle(event)
            }
        }
    }

    private func handle(_ event: RouteUiEvent) {
        switch event {
        case .showError(let error):
            errorMessage = error.message
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

            Spacer()

            Button {
                viewModel.onResetClicked()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(Color.trailGreen)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
        }
    }

    private var zoomControls: some View {
        VStack(spacing: 12) {
            Button {
                zoom(by: 1)
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(Color.trailGreen)
                    .frame(width: 20, height: 20)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }

            Button {
                zoom(by: -1)
            } label: {
                Image(systemName: "minus")
                    .foregroundStyle(Color.trailGreen)
                    .frame(width: 20, height: 20)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
        }
    }

    private func zoom(by delta: Float) {
        guard let mapView else { return }
        mapView.animate(toZoom: mapView.camera.zoom + delta)
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
                        Text("Generate Route")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.trailGreen)
                .disabled(!viewModel.canGenerateRoute)
            }
        }
    }
}
