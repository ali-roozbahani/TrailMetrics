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
import Tracking

struct ContentView: View {
    var body: some View {
        TabView {
            RouteTab()
                .tabItem {
                    Label("Route", systemImage: "map")
                }

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
        }
        .tint(Color.trailGreen)
    }
}

private struct RouteTab: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            RouteView { startPoint, plannedRoutePoints, activityType in
                path.append(
                    TrackingDestination(
                        route: AppRouteTracking(
                            startPoint: startPoint,
                            plannedRoutePoints: plannedRoutePoints,
                            selectedActivityType: activityType
                        )
                    )
                )
            }
            .navigationDestination(for: TrackingDestination.self) { destination in
                TrackingView(
                    activityType: destination.route.selectedActivityType,
                    plannedRoutePoints: destination.route.plannedRoutePoints,
                    startPoint: destination.route.startPoint
                )
                .toolbar(.hidden, for: .tabBar)
            }
        }
    }
}

/// Pairs an `AppRouteTracking` payload with a UUID so each push gets a distinguishing
/// identity independent of the payload's own value equality. `AppRouteTracking` (Kotlin's
/// `AppRoute.Tracking`, bridged) has structural Equatable/Hashable conformance — pushing
/// it directly meant a second "Start Tracking" tap with unchanged Route state (same
/// startPoint/plannedRoutePoints/activityType) produced a value-identical path element to
/// the one just popped, which NavigationPath's diffing silently treated as no change,
/// never invoking `.navigationDestination(for:)`'s builder again. Hashable/Equatable here
/// are keyed on `id` alone, so two pushes are never mistaken for the same path element
/// regardless of what the underlying route data looks like.
private struct TrackingDestination: Hashable {
    let id = UUID()
    let route: AppRouteTracking

    static func == (lhs: TrackingDestination, rhs: TrackingDestination) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

#Preview {
    ContentView()
}
