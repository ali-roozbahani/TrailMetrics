//
//  GMSMapView+ReduceMotion.swift
//  Route
//
//  Camera moves that follow the user's Reduce Motion setting: animated by default, a jump when the user
//  asked for less motion. (The tracking map has its own one-line copy: the packages do not share Maps code.)
//

import GoogleMaps
import UIKit

extension GMSMapView {
    func showLocation(_ location: CLLocationCoordinate2D, zoom: Float) {
        if UIAccessibility.isReduceMotionEnabled {
            moveCamera(GMSCameraUpdate.setTarget(location, zoom: zoom))
        } else {
            animate(toLocation: location)
            animate(toZoom: zoom)
        }
    }

    func showZoom(_ zoom: Float) {
        if UIAccessibility.isReduceMotionEnabled {
            moveCamera(GMSCameraUpdate.zoom(to: zoom))
        } else {
            animate(toZoom: zoom)
        }
    }
}
