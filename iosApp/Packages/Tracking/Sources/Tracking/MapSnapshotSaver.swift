//
//  MapSnapshotSaver.swift
//  Tracking
//

import os
import UIKit

private let snapshotLogger = Logger(subsystem: "dev.roozbahani.trailmetrics.tracking", category: "MapSnapshotSaver")

/// iOS equivalent of Android's `saveSnapshotToFile`: `GMSMapView` has no
/// `map.snapshot(callback)` API like Android's `GoogleMap`, so this renders the map
/// view's current contents directly via `UIGraphicsImageRenderer`. `drawHierarchy` only
/// works on the main thread, so the render stays here and `writeMapSnapshot` does the rest.
@MainActor
func renderMapSnapshot(_ mapView: UIView) -> UIImage {
    let renderer = UIGraphicsImageRenderer(bounds: mapView.bounds)
    return renderer.image { _ in
        mapView.drawHierarchy(in: mapView.bounds, afterScreenUpdates: true)
    }
}

/// The directory the snapshot files live in (`SnapshotFile.swift` in History resolves stored paths
/// against the same one).
func snapshotDirectory() -> URL? {
    guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        snapshotLogger.error("No Application Support directory: the map snapshot is not saved")
        return nil
    }
    return directory
}

/// PNG-encodes `image` and writes it into `directory`. The function is nonisolated, but the app
/// target builds with `NonisolatedNonsendingByDefault`, so it runs on its caller's actor: the caller
/// must hop off the main actor (`TrackingMapView` calls it from `Task.detached`). Returns the file
/// path, or nil when the encoding or the write fails.
func writeMapSnapshot(_ image: UIImage, to directory: URL) async -> String? {
    guard let data = image.pngData() else { return nil }

    let fileName = "activity_\(Int(Date().timeIntervalSince1970 * 1000)).png"
    let fileURL = directory.appendingPathComponent(fileName)

    do {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL)
        return fileURL.path
    } catch {
        return nil
    }
}

/// Removes a snapshot file whose result nobody will receive. Best effort: a file that cannot be
/// removed is an orphaned image the user cannot act on, so the failure is logged. This is file
/// access: the caller must not run it on the main actor (`TrackingMapView` calls it from
/// `Task.detached`).
func discardSnapshotFile(atPath path: String?) {
    guard let path else { return }
    do {
        try FileManager.default.removeItem(atPath: path)
    } catch {
        snapshotLogger.error("Failed to remove discarded map snapshot: \(error.localizedDescription)")
    }
}
