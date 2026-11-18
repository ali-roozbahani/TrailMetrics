# Wrapping a UIKit view, Swift concurrency settings per target

Moved word for word from `SKILL.md`: the sections "Wrapping a UIKit view (the maps)" and "Swift concurrency settings per target". The rules are unchanged; they are still cited as `tm-ios`, "Wrapping a UIKit view (the maps)" and "Swift concurrency settings per target".

## Wrapping a UIKit view (the maps)

- `makeUIView` creates the view and its delegate once; `updateUIView` runs on every state change of
  the SwiftUI parent, so it applies only what changed (compare against what the `Coordinator` last
  applied) instead of clearing and rebuilding the map. Both maps do this (`routeMapChanges(from:to:)` and
  `trackingMapChanges(from:to:)` are the pure, tested parts); a new map view does the same.
- The `Coordinator` keeps what `updateUIView` must remember between calls (the last camera
  coordinates, `planAlreadySeen`), as `RouteMapView` and `TrackingMapView` do. No second strong
  reference to the `GMSMapView` outside the representable: `TrackingMapView`'s comment records the
  dealloc crash that a binding to it caused (`RouteMapView` still has one: `@Binding var mapView`).
- Work that the map needs from the screen (a snapshot) is requested with a value (`snapshotRequestID`)
  and answered by a closure, not by handing the `GMSMapView` out.
- `dismantleUIView` is where the wrapper's own tasks end (`TrackingMapView` cancels `snapshotTask`).

## Swift concurrency settings per target

Read from `iosApp/TrailMetrics.xcodeproj/project.pbxproj` and the six `Package.swift` files; check
them again before relying on them, because they change the meaning of the same code.

| Target | Language mode | Default actor isolation | Approachable concurrency |
|---|---|---|---|
| `TrailMetrics` (app) | 5.0 | `MainActor` | on |
| `TrackingWidgetExtension` | 5.0 | `nonisolated` (unset) | off |
| `TrailMetricsUITests` | 5.0 | `nonisolated` (unset) | off |
| the six packages (tools 5.9) | 5 | `nonisolated` (unset) | off |

So a type in the app target is `@MainActor` without saying it, and a type in a package is not: write
the `@MainActor` on a package type and do not move code between a package and the app target without
re-reading its isolation (D7 in `tm-robustness`).
