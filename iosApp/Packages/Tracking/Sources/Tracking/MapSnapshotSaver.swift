//
//  MapSnapshotSaver.swift
//  Tracking
//

import UIKit

/// iOS equivalent of Android's `saveSnapshotToFile`: `GMSMapView` has no
/// `map.snapshot(callback)` API like Android's `GoogleMap`, so this renders the map
/// view's current contents directly via `UIGraphicsImageRenderer`.
func saveMapSnapshot(_ mapView: UIView) -> String? {
    let renderer = UIGraphicsImageRenderer(bounds: mapView.bounds)
    let image = renderer.image { _ in
        mapView.drawHierarchy(in: mapView.bounds, afterScreenUpdates: true)
    }

    guard let data = image.pngData() else { return nil }
    guard let supportDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first else { return nil }

    let fileName = "activity_\(Int(Date().timeIntervalSince1970 * 1000)).png"
    let fileURL = supportDirectory.appendingPathComponent(fileName)

    do {
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL)
        return fileURL.path
    } catch {
        return nil
    }
}
