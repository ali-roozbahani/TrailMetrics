//
//  RouteMapPlan.swift
//  Route
//
//  What the route map's camera does with a restored plan. The same rule as Android's `isPlanFitNeeded`
//  and `RouteState.planPoints` (feature-route), and as the tracking map's `cameraPlan(for:pathAlreadySeen:)`.
//

import SharedKit

/// A plan whose first waypoints arrive two or more at a time is a restored one.
private let minimumWaypointsToFit = 2

/// Whether the camera fits the whole plan. `planAlreadySeen` is true once non-empty `waypoints` have been
/// handled. A restored plan arrives with two or more waypoints as its first non-empty ones: fit it once.
/// Waypoints the user taps arrive one at a time, so the camera stays where the user moved it.
func isPlanFitNeeded(waypoints: [RoutePoint], planAlreadySeen: Bool) -> Bool {
    !planAlreadySeen && waypoints.count >= minimumWaypointsToFit
}

/// Every point of the plan: the start point, the waypoints and the generated route.
func planPoints(startPoint: Coordinates?, waypoints: [RoutePoint], generatedRoute: Route?) -> [Coordinates] {
    (startPoint.map { [$0] } ?? []) + waypoints.map(\.coordinates) + (generatedRoute?.points.map(\.coordinates) ?? [])
}
