//
//  RouteMapView.swift
//  Route
//

import CoreLocation
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

        updateCamera(mapView, coordinator: context.coordinator)

        mapView.clear()

        if let startPoint {
            let marker = GMSMarker(position: startPoint.locationCoordinate)
            marker.title = String(localized: "Start / Finish", bundle: .module)
            marker.icon = GMSMarker.markerImage(with: .systemGreen)
            marker.map = mapView
        }

        for point in waypoints {
            let marker = GMSMarker(position: point.coordinates.locationCoordinate)
            marker.icon = GMSMarker.markerImage(with: .systemRed)
            marker.userData = point
            marker.map = mapView
        }

        if let generatedRoute {
            let path = GMSMutablePath()
            for point in generatedRoute.points {
                path.add(point.coordinates.locationCoordinate)
            }
            let polyline = GMSPolyline(path: path)
            polyline.strokeWidth = 4
            polyline.strokeColor = UIColor(Color.trailGreen)
            polyline.map = mapView
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
            mapView.animate(toLocation: startPoint.locationCoordinate)
            mapView.animate(toZoom: Self.defaultZoom)
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
