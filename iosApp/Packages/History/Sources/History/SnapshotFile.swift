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

/// Removes the snapshot file with `FileManager`, off the main actor. Best effort, silent on
/// purpose: callers run this only after the activity record is deleted, so a file that can't be
/// removed is just an orphaned image, not worth an error the user can't act on (an exception to
/// `tm-ios`'s "never drop an error" rule).
public struct FileSnapshotDeleter: SnapshotFileDeleting {
    public init() {}

    public func delete(storedPath: String?) async {
        guard let url = resolvedSnapshotURL(forStoredPath: storedPath) else { return }
        // Explicitly detached: without approachable concurrency an `async` function would run
        // on the caller's (main) actor.
        await Task.detached {
            // swiftlint:disable:next optional_try - record already deleted; a leftover file is only an orphaned image
            try? FileManager.default.removeItem(at: url)
        }.value
    }
}
