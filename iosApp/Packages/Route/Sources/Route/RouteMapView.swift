//
//  RouteMapView.swift
//  Route
//

import DesignSystem
import GoogleMaps
import SharedKit
import SwiftUI
import UIKit

struct RouteMapView: UIViewRepresentable {
    private static let defaultZoom: Float = 15
    /// As on the tracking map.
    private static let fitPadding: CGFloat = 64

    let startPoint: Coordinates?
    let waypoints: [RoutePoint]
    let generatedRoute: Route?
    let onMapTapped: (Coordinates) -> Void
    let onWaypointTapped: (RoutePoint) -> Void
    @Binding var mapView: GMSMapView?

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.frame = .zero
        options.camera = GMSCameraPosition.camera(withLatitude: 0, longitude: 0, zoom: Self.defaultZoom)
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator

        DispatchQueue.main.async {
            self.mapView = mapView
        }

        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.parent = self

        let coordinator = context.coordinator

        updateCamera(mapView, coordinator: coordinator)

        let content = RouteMapContent(startPoint: startPoint, waypoints: waypoints, generatedRoute: generatedRoute)
        apply(routeMapChanges(from: coordinator.shown, to: content), of: content, on: mapView, coordinator: coordinator)
        coordinator.shown = content
    }

    /// Only what changed is touched: the markers and the line that stay are the same objects as before.
    private func apply(
        _ changes: RouteMapChanges,
        of content: RouteMapContent,
        on mapView: GMSMapView,
        coordinator: Coordinator
    ) {
        if changes.replacesStartMarker {
            coordinator.startMarker?.map = nil
            coordinator.startMarker = content.startPoint.map { point in
                let marker = GMSMarker(position: point.locationCoordinate)
                marker.title = String(localized: "Start / Finish", bundle: .module)
                marker.icon = GMSMarker.markerImage(with: .systemGreen)
                marker.map = mapView
                return marker
            }
        }

        for point in changes.removedWaypoints {
            coordinator.waypointMarkers.removeValue(forKey: point)?.map = nil
        }
        for point in changes.addedWaypoints {
            let marker = GMSMarker(position: point.coordinates.locationCoordinate)
            marker.icon = GMSMarker.markerImage(with: .systemRed)
            marker.userData = point
            marker.map = mapView
            coordinator.waypointMarkers[point] = marker
        }

        if changes.replacesRouteLine {
            coordinator.routeLine?.map = nil
            coordinator.routeLine = nil
            if !content.routePath.isEmpty {
                let path = GMSMutablePath()
                for coordinates in content.routePath {
                    path.add(coordinates.locationCoordinate)
                }
                let polyline = GMSPolyline(path: path)
                polyline.strokeWidth = 4
                polyline.strokeColor = UIColor(Color.trailGreen)
                polyline.map = mapView
                coordinator.routeLine = polyline
            }
        }
    }

    private func updateCamera(_ mapView: GMSMapView, coordinator: Coordinator) {
        let isFitNeeded = isPlanFitNeeded(waypoints: waypoints, planAlreadySeen: coordinator.planAlreadySeen)
        if !waypoints.isEmpty { coordinator.planAlreadySeen = true }
        if isFitNeeded {
            // A restored plan: all of it in view, once. The map has no size before its first layout, so
            // the fit runs on the next main-actor turn, as on the tracking map.
            var bounds = GMSCoordinateBounds()
            for point in planPoints(startPoint: startPoint, waypoints: waypoints, generatedRoute: generatedRoute) {
                bounds = bounds.includingCoordinate(point.locationCoordinate)
            }
            Task { @MainActor [weak mapView] in
                mapView?.moveCamera(GMSCameraUpdate.fit(bounds, withPadding: Self.fitPadding))
            }
            coordinator.lastCameraCoordinates = startPoint
        } else if let startPoint, coordinator.lastCameraCoordinates != startPoint {
            mapView.showLocation(startPoint.locationCoordinate, zoom: Self.defaultZoom)
            coordinator.lastCameraCoordinates = startPoint
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: RouteMapView
        var lastCameraCoordinates: Coordinates?
        /// True once non-empty waypoints were handled (`isPlanFitNeeded(waypoints:planAlreadySeen:)`). Not
        /// kept across launches: after process death the restored plan is fitted.
        var planAlreadySeen = false
        /// What the map shows now, and the objects that draw it, so an update touches only what changed.
        var shown: RouteMapContent?
        var startMarker: GMSMarker?
        var waypointMarkers: [RoutePoint: GMSMarker] = [:]
        var routeLine: GMSPolyline?

        init(parent: RouteMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let point = marker.userData as? RoutePoint else { return false }
            parent.onWaypointTapped(point)
            return true
        }

        func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onMapTapped(Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
    }
}

private extension Coordinates {
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
