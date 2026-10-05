//
//  SnapshotFileFixture.swift
//  HistoryTests
//

import Foundation

/// A real snapshot file in the test host's Application Support directory, which is where
/// the History package resolves stored snapshot paths (see SnapshotFile.swift).
struct SnapshotFileFixture {
    let url: URL

    /// A path as it was stored at save time: same file name, but under an older app
    /// container, so tests also cover re-resolving the path against the current container.
    var storedPath: String {
        "/old-container/Library/Application Support/\(url.lastPathComponent)"
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func make() throws -> SnapshotFileFixture {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = directory.appendingPathComponent("test-snapshot-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        return SnapshotFileFixture(url: url)
    }

    func remove() {
        // swiftlint:disable:next optional_try - cleanup only; the code under test may already have deleted the file
        try? FileManager.default.removeItem(at: url)
    }
}
