//
//  DetailsMapView.swift
//  History
//

import CoreLocation
import DesignSystem
import GoogleMaps
import SharedKit
import SwiftUI

/// A static, non-interactive counterpart to `Tracking`'s `TrackingMapView`: the same
/// dual-polyline idea (planned route vs. actual/traveled path), but rendered once for a
/// completed activity rather than updated live — no current-location marker, no
/// snapshot-request plumbing, just a single start/finish marker and a camera fit to the
/// recorded path's bounds.
struct DetailsMapView: UIViewRepresentable {
    private static let defaultZoom: Float = 15
    private static let boundsPadding: CGFloat = 48

    let plannedRoutePoints: [Coordinates]
    let actualPath: [Coordinates]

    func makeUIView(context: Context) -> GMSMapView {
        let boundsPoints = actualPath.isEmpty ? plannedRoutePoints : actualPath
        let initialCoordinate = boundsPoints.first?.locationCoordinate ?? kCLLocationCoordinate2DInvalid

        let options = GMSMapViewOptions()
        options.frame = .zero
        options.camera = GMSCameraPosition.camera(
            withTarget: initialCoordinate,
            zoom: Self.defaultZoom
        )
        let mapView = GMSMapView(options: options)

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

        if !actualPath.isEmpty {
            let path = GMSMutablePath()
            for point in actualPath {
                path.add(point.locationCoordinate)
            }
            let polyline = GMSPolyline(path: path)
            polyline.strokeWidth = 4
            polyline.strokeColor = UIColor(Color.trailGreen)
            polyline.map = mapView
        }

        if let startCoordinate = boundsPoints.first {
            let marker = GMSMarker(position: startCoordinate.locationCoordinate)
            marker.title = "Start / Finish"
            marker.icon = GMSMarker.markerImage(with: UIColor(Color.trailGreen))
            marker.map = mapView
        }

        // Deferred to the next run loop turn: `mapView`'s frame is still `.zero` here,
        // before SwiftUI's own layout pass has sized it to the `.frame(height:)` applied
        // where this view is embedded — fitting bounds against a zero-sized view produces
        // a degenerate camera. Same "wait out the current update pass" idiom already used
        // for the snapshot-reset in `TrackingMapView.updateUIView`.
        if boundsPoints.count > 1 {
            DispatchQueue.main.async {
                var bounds = GMSCoordinateBounds()
                for point in boundsPoints {
                    bounds = bounds.includingCoordinate(point.locationCoordinate)
                }
                mapView.moveCamera(.fit(bounds, withPadding: Self.boundsPadding))
            }
        }

        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {}
}

private extension Coordinates {
    var locationCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
