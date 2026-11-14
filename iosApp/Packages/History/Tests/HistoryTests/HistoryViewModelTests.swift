//
//  HistoryViewModelTests.swift
//  HistoryTests
//

import History
import SharedKit
import TestSupport
import XCTest

@MainActor
final class HistoryViewModelTests: XCTestCase {

    func test_init_isLoadingWithNoActivities() {
        let viewModel = HistoryViewModel.subject(repository: FakeActivityHistoryRepository())

        XCTAssertTrue(viewModel.isLoading)
        XCTAssertTrue(viewModel.activities.isEmpty)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func test_observe_publishesLatestEmissionAndStopsLoading() async {
        let repository = FakeActivityHistoryRepository(emissions: [
            [.fixture(id: 1)],
            [.fixture(id: 1), .fixture(id: 2)]
        ])
        let viewModel = HistoryViewModel.subject(repository: repository)

        await viewModel.observe()

        XCTAssertEqual(viewModel.activities.map(\.id), [1, 2])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func test_observe_emptyHistory_isEmpty() async {
        let viewModel = HistoryViewModel.subject(repository: FakeActivityHistoryRepository(emissions: [[]]))

        await viewModel.observe()

        XCTAssertTrue(viewModel.activities.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.isEmpty)
    }

    func test_onDeleteActivity_deletesRecordThenItsSnapshotFileByStoredPath() async {
        let activity = ActivityRecord.fixture(id: 7, snapshotFilePath: "/stored/snapshot-7.png")
        let repository = FakeActivityHistoryRepository(activities: [activity])
        let deleter = FakeSnapshotFileDeleter()
        let viewModel = HistoryViewModel.subject(repository: repository, snapshotFileDeleter: deleter)

        viewModel.onDeleteActivity(activity)

        await waitUntil { !deleter.storedPaths.isEmpty }
        XCTAssertEqual(deleter.storedPaths, ["/stored/snapshot-7.png"])
        XCTAssertEqual(repository.deletedIds, [7])
    }

    func test_onDeleteActivity_withoutSnapshot_deletesRecord() async {
        let activity = ActivityRecord.fixture(id: 8, snapshotFilePath: nil)
        let repository = FakeActivityHistoryRepository(activities: [activity])
        let viewModel = HistoryViewModel.subject(repository: repository)

        viewModel.onDeleteActivity(activity)

        await waitUntil { repository.deletedIds == [8] }
    }

    func test_snapshotURL_isTheKotlinResolutionOfTheStoredPath() {
        let activity = ActivityRecord.fixture(id: 9, snapshotFilePath: "/old-container/snapshot-9.png")
        let deleter = FakeSnapshotFileDeleter(resolvedPath: "/current/snapshot-9.png")
        let viewModel = HistoryViewModel.subject(
            repository: FakeActivityHistoryRepository(activities: [activity]),
            snapshotFileDeleter: deleter
        )

        let url = viewModel.snapshotURL(for: activity)

        XCTAssertEqual(url, URL(fileURLWithPath: "/current/snapshot-9.png"))
        XCTAssertEqual(deleter.resolvedStoredPaths, ["/old-container/snapshot-9.png"])
    }

    func test_snapshotURL_isNilWhenKotlinResolvesNoFile() {
        let activity = ActivityRecord.fixture(id: 10, snapshotFilePath: "/")
        let viewModel = HistoryViewModel.subject(
            repository: FakeActivityHistoryRepository(activities: [activity]),
            snapshotFileDeleter: FakeSnapshotFileDeleter(resolvedPath: nil)
        )

        XCTAssertNil(viewModel.snapshotURL(for: activity))
    }
}
