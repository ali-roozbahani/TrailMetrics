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
/// changes these names the count is -1, which the UI tests report as such.
@MainActor
enum UITestWaypointCount {
    /// The waypoint count of the Route map, or -1 if the map or its state is not found.
    static func current() -> Int {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if let count = count(in: window) { return count }
            }
        }
        return -1
    }

    private static func count(in view: UIView) -> Int? {
        if String(describing: type(of: view)) == "GMSMapView",
           let delegate = view.value(forKey: "delegate"),
           let parent = child(named: "parent", of: delegate),
           let waypoints = child(named: "waypoints", of: parent) {
            return Mirror(reflecting: waypoints).children.count
        }
        for subview in view.subviews {
            if let count = count(in: subview) { return count }
        }
        return nil
    }

    private static func child(named name: String, of value: Any) -> Any? {
        Mirror(reflecting: value).children.first { $0.label == name }?.value
    }
}
#endif
