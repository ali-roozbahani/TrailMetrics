//
//  RouteView.swift
//  Route
//

import SharedKit
import SwiftUI

public struct RouteView: View {
    @StateObject private var viewModel = RouteViewModel()
    @StateObject private var permissionRequester = LocationPermissionRequester()
    @State private var showProfileSheet = false
    @State private var errorMessage: String?

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
                onWaypointTapped: viewModel.onWaypointRemoved
            )
            .ignoresSafeArea()

            if viewModel.startPoint == nil {
                ProgressView()
            }

            VStack {
                topBar
                Spacer()
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
        case .requestLocationPermission:
            permissionRequester.request { viewModel.onLocationPermissionGranted() }
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
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }

            Spacer()

            Button {
                viewModel.onResetClicked()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
        }
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
                .disabled(!viewModel.canGenerateRoute)
            }
        }
    }
}
