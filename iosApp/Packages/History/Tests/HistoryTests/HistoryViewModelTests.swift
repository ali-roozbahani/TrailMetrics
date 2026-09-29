//
//  HistoryViewModelTests.swift
//  HistoryTests
//

import History
import SharedKit
import XCTest

@MainActor
final class HistoryViewModelTests: XCTestCase {

    func test_init_isLoadingWithNoActivities() {
        let viewModel = HistoryViewModel(activityHistoryRepository: FakeActivityHistoryRepository())

        XCTAssertTrue(viewModel.isLoading)
        XCTAssertTrue(viewModel.activities.isEmpty)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func test_observe_publishesLatestEmissionAndStopsLoading() async {
        let repository = FakeActivityHistoryRepository(emissions: [
            [.fixture(id: 1)],
            [.fixture(id: 1), .fixture(id: 2)]
        ])
        let viewModel = HistoryViewModel(activityHistoryRepository: repository)

        await viewModel.observe()

        XCTAssertEqual(viewModel.activities.map(\.id), [1, 2])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func test_observe_emptyHistory_isEmpty() async {
        let viewModel = HistoryViewModel(
            activityHistoryRepository: FakeActivityHistoryRepository(emissions: [[]])
        )

        await viewModel.observe()

        XCTAssertTrue(viewModel.activities.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.isEmpty)
    }

    func test_onDeleteActivity_deletesRecordAndItsSnapshotFile() async throws {
        let snapshot = try SnapshotFileFixture.make()
        defer { snapshot.remove() }
        let activity = ActivityRecord.fixture(id: 7, snapshotFilePath: snapshot.storedPath)
        let repository = FakeActivityHistoryRepository(activities: [activity])
        let viewModel = HistoryViewModel(activityHistoryRepository: repository)

        viewModel.onDeleteActivity(activity)

        await waitUntil { !snapshot.exists }
        XCTAssertEqual(repository.deletedIds, [7])
    }

    func test_onDeleteActivity_withoutSnapshot_deletesRecord() async {
        let activity = ActivityRecord.fixture(id: 8, snapshotFilePath: nil)
        let repository = FakeActivityHistoryRepository(activities: [activity])
        let viewModel = HistoryViewModel(activityHistoryRepository: repository)

        viewModel.onDeleteActivity(activity)

        await waitUntil { repository.deletedIds == [8] }
    }
}
