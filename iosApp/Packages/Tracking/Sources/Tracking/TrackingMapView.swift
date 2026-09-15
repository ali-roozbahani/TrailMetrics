//
//  TrackingMapView.swift
//  Tracking
//

import CoreLocation
import GoogleMaps
import SharedKit
import SwiftUI
import UIKit

/// A dedicated map view rather than reusing `Route`'s `RouteMapView`: that type is
/// internal to the `Route` package (not reusable across SPM package boundaries) and is
/// shaped around Route-specific concerns (waypoint tap handling, a single generated
/// route polyline) that don't apply here — Tracking instead needs two independent
/// polylines (planned vs. traveled) plus a moving current-location marker, with no tap
/// handling at all.
struct TrackingMapView: UIViewRepresentable {
    private static let defaultZoom: Float = 15

    /// A plain circular dot, matching Android's `CurrentLocationMarker` (20dp circle,
    /// trailGreen fill, 3dp white border, centered on the coordinate) — rather than
    /// GMSMarker's default pin-shaped image, which reads as a place marker, not a
    /// live position indicator.
    private static let currentLocationMarkerImage: UIImage = {
        let diameter: CGFloat = 20
        let borderWidth: CGFloat = 3
        let size = CGSize(width: diameter, height: diameter)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let outerRect = CGRect(origin: .zero, size: size)
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: outerRect)

            let innerRect = outerRect.insetBy(dx: borderWidth, dy: borderWidth)
            UIColor(Color.trailGreen).setFill()
            context.cgContext.fillEllipse(in: innerRect)
        }
    }()

    let startPoint: Coordinates
    let plannedRoutePoints: [Coordinates]
    let traveledSegment: [Coordinates]
    let currentLocation: Coordinates?

    // Inversion of control for the Finish-snapshot flow: TrackingView never holds a
    // raw GMSMapView. It requests a snapshot by writing a new UUID here; this view is
    // the only thing that ever touches the live GMSMapView (via the `mapView`
    // parameter `updateUIView` already receives on every call — no separate stored
    // reference needed), and reports the result back through `onSnapshotReady`. This
    // was previously a `@Binding var mapView: GMSMapView?` plus a `mapView = nil`
    // reset at three call sites in TrackingView — a second, independently-timed
    // strong reference to the map view that raced against SwiftUI's own single
    // UIViewRepresentable teardown pass and caused a GMSMapView dealloc crash.
    // Removing that second reference entirely (rather than timing it more carefully)
    // is the fix.
    @Binding var snapshotRequestID: UUID?
    let onSnapshotReady: (String?) -> Void

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.frame = .zero
        options.camera = GMSCameraPosition.camera(
            withLatitude: startPoint.latitude,
            longitude: startPoint.longitude,
            zoom: Self.defaultZoom
        )
        return GMSMapView(options: options)
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        mapView.clear()

        if !plannedRoutePoints.isEmpty {
            let path = GMSMutablePath()
            for point in plannedRoutePoints {
                path.add(point.locationCoordinate)
            }
            let polyline = GMSPolyline(path: path)
            polyline.strokeWidth = 4
            polyline.strokeColor = .systemGray
            polyline.map = mapView
        }

        if !traveledSegment.isEmpty {
            let path = GMSMutablePath()
            for point in traveledSegment {
                path.add(point.locationCoordinate)
            }
            let polyline = GMSPolyline(path: path)
            polyline.strokeWidth = 4
            polyline.strokeColor = UIColor(Color.trailGreen)
            polyline.map = mapView
        }

        let markerCoordinates = currentLocation ?? startPoint
        let marker = GMSMarker(position: markerCoordinates.locationCoordinate)
        marker.icon = Self.currentLocationMarkerImage
        marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
        marker.map = mapView

        if context.coordinator.lastCameraCoordinates != markerCoordinates {
            mapView.animate(toLocation: markerCoordinates.locationCoordinate)
            context.coordinator.lastCameraCoordinates = markerCoordinates
        }

        if let requestID = snapshotRequestID, requestID != context.coordinator.handledSnapshotRequestID {
            context.coordinator.handledSnapshotRequestID = requestID
            let snapshotFilePath = saveMapSnapshot(mapView)
            // Deferred: mutating @State synchronously from within an active SwiftUI
            // update pass (which updateUIView is always called as part of) is a
            // known hazard, so the reset is scheduled for the next run loop turn.
            DispatchQueue.main.async {
                snapshotRequestID = nil
            }
            onSnapshotReady(snapshotFilePath)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastCameraCoordinates: Coordinates?
        var handledSnapshotRequestID: UUID?
    }
}

private extension Coordinates {
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
