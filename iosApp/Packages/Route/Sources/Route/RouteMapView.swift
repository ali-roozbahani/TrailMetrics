//
//  RouteMapView.swift
//  Route
//

import CoreLocation
import GoogleMaps
import SharedKit
import SwiftUI

struct RouteMapView: UIViewRepresentable {
    private static let defaultZoom: Float = 15

    let startPoint: Coordinates?
    let waypoints: [RoutePoint]
    let generatedRoute: Route?
    let onMapTapped: (Coordinates) -> Void
    let onWaypointTapped: (RoutePoint) -> Void

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withLatitude: 0, longitude: 0, zoom: Self.defaultZoom)
        let mapView = GMSMapView(frame: .zero, camera: camera)
        mapView.delegate = context.coordinator
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.parent = self

        if let startPoint, context.coordinator.lastCameraCoordinates != startPoint {
            mapView.animate(toLocation: startPoint.locationCoordinate)
            mapView.animate(toZoom: Self.defaultZoom)
            context.coordinator.lastCameraCoordinates = startPoint
        }

        mapView.clear()

        if let startPoint {
            let marker = GMSMarker(position: startPoint.locationCoordinate)
            marker.title = "Start / Finish"
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

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: RouteMapView
        var lastCameraCoordinates: Coordinates?

        init(parent: RouteMapView) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            parent.onMapTapped(Coordinates(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let point = marker.userData as? RoutePoint else { return false }
            parent.onWaypointTapped(point)
            return true
        }
    }
}

private extension Coordinates {
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
