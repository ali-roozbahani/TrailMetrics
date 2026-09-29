//
//  RouteFixtures.swift
//  RouteTests
//

import SharedKit

enum RouteFixtures {
    static let startPoint = Coordinates(latitude: 52.37, longitude: 4.89)

    /// Distinct, deterministic coordinates for the `index`-th tapped waypoint.
    static func waypoint(_ index: Int) -> Coordinates {
        Coordinates(latitude: 52.0 + Double(index) / 100, longitude: 4.0 + Double(index) / 100)
    }

    static let route = Route(
        points: [
            RoutePoint(coordinates: startPoint, order: 0),
            RoutePoint(coordinates: waypoint(0), order: 1),
            RoutePoint(coordinates: waypoint(1), order: 2),
            RoutePoint(coordinates: startPoint, order: 3)
        ],
        distanceMeters: 1_250
    )
}
