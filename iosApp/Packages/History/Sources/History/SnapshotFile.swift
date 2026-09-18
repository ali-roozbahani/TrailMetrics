//
//  SnapshotFile.swift
//  History
//

import Foundation

// `ActivityRecord.snapshotFilePath` is a full path captured at save time (see
// MapSnapshotSaver.swift), but the Application Support directory's container UUID is not
// stable across reinstalls (confirmed on-device: a plain reinstall mints a new container
// while carrying the same file over under the same name) — the old absolute path then
// points at a container that no longer exists. Re-resolving just the filename against the
// *current* Application Support directory keeps both display and deletion working across
// reinstalls without needing to change what's stored.
func resolvedSnapshotURL(forStoredPath path: String?) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    guard let supportDirectory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first else { return nil }
    let fileName = (path as NSString).lastPathComponent
    return supportDirectory.appendingPathComponent(fileName)
}

func deleteSnapshotFile(forStoredPath path: String?) {
    guard let url = resolvedSnapshotURL(forStoredPath: path) else { return }
    try? FileManager.default.removeItem(at: url)
}
