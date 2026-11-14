//
//  FileSnapshotDeleterTests.swift
//  HistoryTests
//

import History
import XCTest

final class FileSnapshotDeleterTests: XCTestCase {

    func test_delete_removesTheFileOfTheStoredPath() async throws {
        let snapshot = try SnapshotFileFixture.make()
        defer { snapshot.remove() }

        await FileSnapshotDeleter().delete(storedPath: snapshot.storedPath)

        XCTAssertFalse(snapshot.exists)
    }

    func test_delete_nilPath_doesNothing() async {
        await FileSnapshotDeleter().delete(storedPath: nil)
    }

    func test_delete_emptyPath_doesNothing() async {
        await FileSnapshotDeleter().delete(storedPath: "")
    }

    func test_delete_missingFile_doesNotThrowOrAffectOtherFiles() async throws {
        let other = try SnapshotFileFixture.make()
        defer { other.remove() }

        await FileSnapshotDeleter().delete(storedPath: "/old-container/missing-\(UUID().uuidString).png")

        XCTAssertTrue(other.exists)
    }
}
