#if UITEST_SEAM
//
//  UITestWaypointCount.swift
//  TrailMetrics
//

import UIKit

// UI-TEST SUPPORT ONLY. Compiled only in the Debug-UITest build configuration (UITEST_SEAM).

/// The number of waypoints the Route screen shows, for the probe. The waypoints live in the Swift
/// `RouteViewModel` of the Route package, which the app target cannot reach and which has no
/// UI-test condition, so the count is read from what the map was last given: the Google map view's
/// delegate is the Route package's coordinator, whose `parent` holds the `waypoints` the map
/// drew its markers from. Reflection keeps the production code untouched; if the Route package
/// changes these names the count is -1, which the UI tests report as such. `routeMap()` is the
/// finder `UITestWaypointSeam` shares.
@MainActor
enum UITestWaypointCount {
    /// The waypoint count of the Route map, or -1 if the map or its state is not found.
    static func current() -> Int {
        guard let map = routeMap(), let waypoints = waypoints(of: map) else { return -1 }
        return Mirror(reflecting: waypoints).children.count
    }

    /// The `GMSMapView` of the Route screen: the first one whose delegate has the waypoints.
    static func routeMap() -> UIView? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let map = routeMap(in: window) { return map }
            }
        }
        return nil
    }

    private static func routeMap(in view: UIView) -> UIView? {
        if String(describing: type(of: view)) == "GMSMapView", waypoints(of: view) != nil {
            return view
        }
        for subview in view.subviews {
            if let map = routeMap(in: subview) { return map }
        }
        return nil
    }

    private static func waypoints(of map: UIView) -> Any? {
        guard let delegate = map.value(forKey: "delegate"),
              let parent = child(named: "parent", of: delegate) else { return nil }
        return child(named: "waypoints", of: parent)
    }

    private static func child(named name: String, of value: Any) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == name }?.value
    }
}
#endif
