#if UITEST_SEAM
//
//  UITestWaypointSeam.swift
//  TrailMetrics
//

import CoreLocation
import GoogleMaps
import UIKit

// UI-TEST SUPPORT ONLY. Compiled only in the Debug-UITest build configuration (UITEST_SEAM).

/// Adds a Route waypoint without a map long press, for the probe's `uitest.probe.addWaypoint`.
/// It finds the Route map (`UITestWaypointCount.routeMap()`), turns the next point of a fixed list
/// of normalized map points into a coordinate with the map's projection and calls the map
/// delegate's public `mapView(_:didLongPressAt:)`, which is what the Maps SDK calls after a
/// recognized long press: the Route coordinator, the view model and the markers all run as for a
/// real press; only the SDK's gesture recognition is skipped. The points are the ones the UI
/// tests' long-press helper uses, in the same order.
@MainActor
enum UITestWaypointSeam {
    private static let points = [
        CGVector(dx: 0.25, dy: 0.42),
        CGVector(dx: 0.75, dy: 0.42),
        CGVector(dx: 0.5, dy: 0.6),
        CGVector(dx: 0.25, dy: 0.6),
        CGVector(dx: 0.7, dy: 0.55)
    ]
    private static var nextIndex = 0

    /// Adds the next waypoint and returns true. Returns false, without advancing, if the list is
    /// used up or the map, its size, its delegate or the coordinate is not available.
    @discardableResult
    static func addNext() -> Bool {
        guard nextIndex < points.count,
              let mapView = UITestWaypointCount.routeMap() as? GMSMapView,
              let delegate = mapView.delegate,
              mapView.bounds.width > 0, mapView.bounds.height > 0 else { return false }
        let point = points[nextIndex]
        let coordinate = mapView.projection.coordinate(
            for: CGPoint(x: mapView.bounds.width * point.dx, y: mapView.bounds.height * point.dy)
        )
        guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
        delegate.mapView?(mapView, didLongPressAt: coordinate)
        nextIndex += 1
        return true
    }
}
#endif
