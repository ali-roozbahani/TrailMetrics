//
//  DetailsViewModelTests.swift
//  HistoryTests
//

import History
import SharedKit
import TestSupport
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

    func test_onDeleteConfirmed_deletesRecordAndSnapshotThenCallsOnDeletedOnce() async {
        let repository = FakeActivityHistoryRepository(
            activities: [.fixture(id: 42, snapshotFilePath: "/stored/snapshot-42.png")]
        )
        let deleter = FakeSnapshotFileDeleter()
        let viewModel = DetailsViewModel(
            activityId: 42,
            activityHistoryRepository: repository,
            snapshotFileDeleter: deleter
        )
        await waitUntil { !viewModel.isLoading }

        var onDeletedCallCount = 0
        var deletedIdsWhenCalled: [Int64] = []
        var deletedPathsWhenCalled: [String?] = []
        viewModel.onDeleteConfirmed {
            onDeletedCallCount += 1
            deletedIdsWhenCalled = repository.deletedIds
            deletedPathsWhenCalled = deleter.storedPaths
        }

        await waitUntil { onDeletedCallCount > 0 }
        await Task.yield()

        XCTAssertEqual(onDeletedCallCount, 1)
        XCTAssertEqual(deletedIdsWhenCalled, [42])
        XCTAssertEqual(deletedPathsWhenCalled, ["/stored/snapshot-42.png"])
    }

    func test_onDeleteConfirmed_callsOnDeletedOnlyAfterTheSnapshotDeleterReturned() async {
        let repository = FakeActivityHistoryRepository(
            activities: [.fixture(id: 42, snapshotFilePath: "/stored/snapshot-42.png")]
        )
        let deleter = FakeSnapshotFileDeleter(isHolding: true)
        let viewModel = DetailsViewModel(
            activityId: 42,
            activityHistoryRepository: repository,
            snapshotFileDeleter: deleter
        )
        await waitUntil { !viewModel.isLoading }

        var onDeletedCallCount = 0
        viewModel.onDeleteConfirmed { onDeletedCallCount += 1 }
        await waitUntil { !deleter.storedPaths.isEmpty }
        await Task.yield()
        XCTAssertEqual(onDeletedCallCount, 0)

        deleter.release()

        await waitUntil { onDeletedCallCount > 0 }
        await Task.yield()
        XCTAssertEqual(onDeletedCallCount, 1)
    }
}
