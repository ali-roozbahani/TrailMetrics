//
//  SnapshotFile.swift
//  History
//

import Foundation
import SharedKit

extension SnapshotFileDeleter {
    /// The URL of the snapshot image that a stored path names, or nil when there is none. The
    /// resolution is Kotlin's `SnapshotFileDeleter.resolve`, the one `delete` uses, so a stored
    /// path shows the file it deletes (the old container's absolute path included, see
    /// `IosSnapshotFileDeleter`).
    func snapshotURL(forStoredPath storedPath: String?) -> URL? {
        resolve(storedPath: storedPath).map { URL(fileURLWithPath: $0) }
    }

    /// Best effort: the callers run this only after the activity record is deleted, so a file that
    /// can't be removed is just an orphaned image, not worth an error the user can't act on (an
    /// exception to `tm-ios`'s "never drop an error" rule).
    func deleteBestEffort(storedPath: String?) async {
        // swiftlint:disable:next optional_try - record already deleted; a leftover file is only an orphaned image
        try? await delete(storedPath: storedPath)
    }
}
