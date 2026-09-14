//
//  ContentView.swift
//  TrailMetrics
//
//  Created by Ali Roozbahani on 07.09.26.
//

import History
import Route
import SharedKit
import SwiftUI

struct ContentView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            RouteView { startPoint, plannedRoutePoints, activityType in
                path.append(
                    AppRouteTracking(
                        startPoint: startPoint,
                        plannedRoutePoints: plannedRoutePoints,
                        selectedActivityType: activityType
                    )
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: AppRouteHistory.shared) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .navigationDestination(for: AppRouteTracking.self) { route in
                TrackingPlaceholderView(route: route)
            }
            .navigationDestination(for: AppRouteHistory.self) { _ in
                HistoryView()
            }
        }
    }
}

private struct TrackingPlaceholderView: View {
    let route: AppRouteTracking

    var body: some View {
        // Deliberate placeholder for the not-yet-built Tracking feature package, not an oversight.
        // swiftlint:disable:next todo
        // TODO: Replace with the Tracking feature package once it exists.
        VStack(spacing: 12) {
            Text("Tracking - TODO")
                .font(.title2)
            Text("\(route.plannedRoutePoints.count) planned route point(s)")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
