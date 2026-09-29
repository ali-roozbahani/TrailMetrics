//
//  DetailsViewModelTests.swift
//  HistoryTests
//

import History
import SharedKit
import XCTest

@MainActor
final class DetailsViewModelTests: XCTestCase {

    func test_init_isLoadingUntilActivityArrives() {
        let viewModel = DetailsViewModel(
            activityId: 42,
            activityHistoryRepository: FakeActivityHistoryRepository(activities: [.fixture(id: 42)])
        )

        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.activity)
    }

    func test_init_loadsActivityById() async {
        let repository = FakeActivityHistoryRepository(activities: [.fixture(id: 41), .fixture(id: 42)])
        let viewModel = DetailsViewModel(activityId: 42, activityHistoryRepository: repository)

        await waitUntil { !viewModel.isLoading }

        XCTAssertEqual(viewModel.activity?.id, 42)
        XCTAssertEqual(repository.requestedIds, [42])
    }

    func test_init_unknownId_stopsLoadingWithoutActivity() async {
        let viewModel = DetailsViewModel(
            activityId: 99,
            activityHistoryRepository: FakeActivityHistoryRepository(activities: [.fixture(id: 42)])
        )

        await waitUntil { !viewModel.isLoading }

        XCTAssertNil(viewModel.activity)
    }

    func test_onDeleteConfirmed_deletesRecordAndSnapshotThenCallsOnDeletedOnce() async throws {
        let snapshot = try SnapshotFileFixture.make()
        defer { snapshot.remove() }
        let repository = FakeActivityHistoryRepository(
            activities: [.fixture(id: 42, snapshotFilePath: snapshot.storedPath)]
        )
        let viewModel = DetailsViewModel(activityId: 42, activityHistoryRepository: repository)
        await waitUntil { !viewModel.isLoading }

        var onDeletedCallCount = 0
        var deletedIdsWhenCalled: [Int64] = []
        var snapshotExistedWhenCalled = true
        viewModel.onDeleteConfirmed {
            onDeletedCallCount += 1
            deletedIdsWhenCalled = repository.deletedIds
            snapshotExistedWhenCalled = snapshot.exists
        }

        await waitUntil { onDeletedCallCount > 0 }
        await Task.yield()

        XCTAssertEqual(onDeletedCallCount, 1)
        XCTAssertEqual(deletedIdsWhenCalled, [42])
        XCTAssertFalse(snapshotExistedWhenCalled)
    }
}
