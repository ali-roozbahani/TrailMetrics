//
//  TrackingMapView.swift
//  Tracking
//

import CoreLocation
import DesignSystem
import GoogleMaps
import SharedKit
import SwiftUI
import UIKit

/// A dedicated map view rather than reusing `Route`'s `RouteMapView`: that type is
/// internal to the `Route` package (not reusable across SPM package boundaries) and is
/// shaped around Route-specific concerns (waypoint tap handling, a single generated
/// route polyline) that don't apply here — Tracking instead needs three independent
/// polylines (planned, traveled, recorded) plus a moving current-location marker, with no tap
/// handling at all.
struct TrackingMapView: UIViewRepresentable {
    private static let defaultZoom: Float = 15
    private static let fitPadding: CGFloat = 64

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
    /// The GPS points of the session, drawn above the planned route and the traveled segment.
    let recordedPath: [Coordinates]
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

        addPolyline(plannedRoutePoints, color: .systemGray, to: mapView)
        addPolyline(traveledSegment, color: UIColor(Color.trailGreen), to: mapView)
        addPolyline(recordedPathToDraw(recordedPath), color: UIColor(Color.trailGreen), to: mapView)

        let markerCoordinates = currentLocation ?? startPoint
        let marker = GMSMarker(position: markerCoordinates.locationCoordinate)
        marker.icon = Self.currentLocationMarkerImage
        marker.groundAnchor = CGPoint(x: 0.5, y: 0.5)
        marker.map = mapView

        updateCamera(mapView, markerCoordinates: markerCoordinates, coordinator: context.coordinator)

        if let requestID = snapshotRequestID, requestID != context.coordinator.handledSnapshotRequestID {
            context.coordinator.handledSnapshotRequestID = requestID
            // The render needs the main thread; the PNG encoding and the write run off it.
            let image = renderMapSnapshot(mapView)
            let coordinator = context.coordinator
            coordinator.snapshotTask?.cancel()
            coordinator.snapshotTask = Task {
                let path: String?
                if let directory = snapshotDirectory() {
                    // Explicit hop: the encoding and the write must not run on the main actor.
                    path = await Task.detached { await writeMapSnapshot(image, to: directory) }.value
                } else {
                    path = nil
                }
                // A result for a request that was cancelled (the map view went away) or replaced
                // is dropped, and its file removed.
                guard !Task.isCancelled, coordinator.handledSnapshotRequestID == requestID else {
                    // File access: off the main actor, like the write.
                    Task.detached { discardSnapshotFile(atPath: path) }
                    return
                }
                // The binding is reset only now, so the Finish tap guard
                // (`TrackingView.finishTracking`) holds until the path is delivered.
                snapshotRequestID = nil
                onSnapshotReady(path)
            }
        }
    }

    private func addPolyline(_ points: [Coordinates], color: UIColor, to mapView: GMSMapView) {
        guard !points.isEmpty else { return }
        let path = GMSMutablePath()
        for point in points {
            path.add(point.locationCoordinate)
        }
        let polyline = GMSPolyline(path: path)
        polyline.strokeWidth = 4
        polyline.strokeColor = color
        polyline.map = mapView
    }

    private func updateCamera(_ mapView: GMSMapView, markerCoordinates: Coordinates, coordinator: Coordinator) {
        let plan = cameraPlan(for: recordedPath, pathAlreadySeen: coordinator.pathAlreadySeen)
        if !recordedPath.isEmpty { coordinator.pathAlreadySeen = true }
        if plan == .fitPath {
            // A restored session: all of its path in view, once. The map has no size before its first
            // layout, so the fit runs on the next main-actor turn.
            var bounds = GMSCoordinateBounds()
            for point in recordedPath {
                bounds = bounds.includingCoordinate(point.locationCoordinate)
            }
            Task { @MainActor [weak mapView] in
                mapView?.moveCamera(GMSCameraUpdate.fit(bounds, withPadding: Self.fitPadding))
            }
            coordinator.lastCameraCoordinates = markerCoordinates
        } else if coordinator.lastCameraCoordinates != markerCoordinates {
            mapView.animate(toLocation: markerCoordinates.locationCoordinate)
            coordinator.lastCameraCoordinates = markerCoordinates
        }
    }

    static func dismantleUIView(_ mapView: GMSMapView, coordinator: Coordinator) {
        coordinator.snapshotTask?.cancel()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastCameraCoordinates: Coordinates?
        /// True once a non-empty recorded path was handled (`cameraPlan(for:pathAlreadySeen:)`).
        var pathAlreadySeen = false
        var handledSnapshotRequestID: UUID?
        var snapshotTask: Task<Void, Never>?
    }
}

private extension Coordinates {
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
