//
//  MapSnapshotWriterTests.swift
//  TrackingTests
//

@testable import Tracking
import UIKit
import XCTest

final class MapSnapshotWriterTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func image() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
    }

    func test_write_createsPngFileInDirectory() async throws {
        let path = await writeMapSnapshot(image(), to: directory)

        let writtenPath = try XCTUnwrap(path)
        let url = URL(fileURLWithPath: writtenPath)
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
        XCTAssertTrue(url.lastPathComponent.hasPrefix("activity_"))
        XCTAssertEqual(url.pathExtension, "png")
        XCTAssertNotNil(UIImage(contentsOfFile: writtenPath))
    }

    func test_write_unwritableDirectory_returnsNil() async throws {
        // A regular file where the directory should be: creating the directory fails.
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: blocker)

        let path = await writeMapSnapshot(image(), to: blocker.appendingPathComponent("sub"))

        XCTAssertNil(path)
        try FileManager.default.removeItem(at: blocker)
    }

    func test_discard_removesFile() async throws {
        let written = await writeMapSnapshot(image(), to: directory)
        let path = try XCTUnwrap(written)

        discardSnapshotFile(atPath: path)

        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }
}
