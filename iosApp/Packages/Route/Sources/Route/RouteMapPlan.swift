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

/// What the route map shows: the start marker, one marker per waypoint and the generated route's line.
struct RouteMapContent: Equatable {
    var startPoint: Coordinates?
    var waypoints: [RoutePoint]
    var routePath: [Coordinates]

    init(startPoint: Coordinates?, waypoints: [RoutePoint], generatedRoute: Route?) {
        self.startPoint = startPoint
        self.waypoints = waypoints
        self.routePath = generatedRoute?.points.map(\.coordinates) ?? []
    }
}

/// What the map has to change to go from the content it shows to the new one.
struct RouteMapChanges: Equatable {
    /// The start marker is replaced (removed, and added again when there is a start point).
    var replacesStartMarker: Bool
    var removedWaypoints: [RoutePoint]
    var addedWaypoints: [RoutePoint]
    /// The route line is replaced (removed, and drawn again when the path is not empty).
    var replacesRouteLine: Bool

    var isEmpty: Bool {
        !replacesStartMarker && removedWaypoints.isEmpty && addedWaypoints.isEmpty && !replacesRouteLine
    }
}

/// `old` is nil before the map shows anything. The map is never cleared as a whole: only what differs.
func routeMapChanges(from old: RouteMapContent?, to new: RouteMapContent) -> RouteMapChanges {
    let oldWaypoints = old?.waypoints ?? []
    return RouteMapChanges(
        replacesStartMarker: old?.startPoint != new.startPoint,
        removedWaypoints: oldWaypoints.filter { !new.waypoints.contains($0) },
        addedWaypoints: new.waypoints.filter { !oldWaypoints.contains($0) },
        replacesRouteLine: (old?.routePath ?? []) != new.routePath
    )
}
