//
//  DetailsViewModelFailureTests.swift
//  HistoryTests
//

import History
import SharedKit
import TestSupport
import XCTest

@MainActor
final class DetailsViewModelFailureTests: XCTestCase {

    private let generalErrorMessage = "Something went wrong. Please try again."

    func test_init_failedLoad_stopsLoadingWithoutActivityAndShowsError() async {
        let repository = FakeActivityHistoryRepository(activities: [.fixture(id: 42)])
        repository.setFailing(true)
        let viewModel = DetailsViewModel(activityId: 42, activityHistoryRepository: repository)

        await waitUntil { !viewModel.isLoading }

        XCTAssertNil(viewModel.activity)
        XCTAssertEqual(viewModel.errorMessage, generalErrorMessage)

        viewModel.onErrorDismissed()
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_onDeleteConfirmed_twiceBackToBack_deletesOnceAndCallsOnDeletedOnce() async {
        let repository = FakeActivityHistoryRepository(activities: [.fixture(id: 42), .fixture(id: 43)])
        let viewModel = await loadedViewModel(activityId: 42, repository: repository)

        var onDeletedCallCount = 0
        viewModel.onDeleteConfirmed { onDeletedCallCount += 1 }
        viewModel.onDeleteConfirmed { onDeletedCallCount += 1 }
        await waitUntil { onDeletedCallCount > 0 }

        await deleteBarrier(sharing: repository)
        XCTAssertEqual(onDeletedCallCount, 1)
        XCTAssertEqual(repository.deletedIds.filter { $0 != 43 }, [42])
    }

    func test_onDeleteConfirmed_failedDelete_keepsSnapshotShowsErrorAndStaysOpen() async {
        let repository = FakeActivityHistoryRepository(
            activities: [.fixture(id: 42, snapshotFilePath: "/stored/snapshot-42.png")]
        )
        let deleter = FakeSnapshotFileDeleter()
        let viewModel = await loadedViewModel(activityId: 42, repository: repository, deleter: deleter)
        repository.setFailing(true)

        var onDeletedCallCount = 0
        viewModel.onDeleteConfirmed { onDeletedCallCount += 1 }
        await waitUntil { viewModel.errorMessage != nil }
        await Task.yield()

        XCTAssertEqual(viewModel.errorMessage, generalErrorMessage)
        XCTAssertEqual(onDeletedCallCount, 0)
        XCTAssertTrue(deleter.storedPaths.isEmpty)
        XCTAssertTrue(repository.deletedIds.isEmpty)
    }

    func test_onDeleteConfirmed_afterFailedDelete_deletesOnRetry() async {
        let repository = FakeActivityHistoryRepository(
            activities: [.fixture(id: 42, snapshotFilePath: "/stored/snapshot-42.png")]
        )
        let deleter = FakeSnapshotFileDeleter()
        let viewModel = await loadedViewModel(activityId: 42, repository: repository, deleter: deleter)
        repository.setFailing(true)
        var onDeletedCallCount = 0
        viewModel.onDeleteConfirmed { onDeletedCallCount += 1 }
        await waitUntil { viewModel.errorMessage != nil }
        XCTAssertEqual(onDeletedCallCount, 0)

        repository.setFailing(false)
        viewModel.onDeleteConfirmed { onDeletedCallCount += 1 }

        await waitUntil { onDeletedCallCount > 0 }
        await Task.yield()
        XCTAssertEqual(onDeletedCallCount, 1)
        XCTAssertEqual(repository.deletedIds, [42])
        XCTAssertEqual(deleter.storedPaths, ["/stored/snapshot-42.png"])
    }

    private func loadedViewModel(
        activityId: Int64,
        repository: FakeActivityHistoryRepository,
        deleter: FakeSnapshotFileDeleter = FakeSnapshotFileDeleter()
    ) async -> DetailsViewModel {
        let viewModel = DetailsViewModel(
            activityId: activityId,
            activityHistoryRepository: repository,
            snapshotFileDeleter: deleter
        )
        await waitUntil { !viewModel.isLoading }
        return viewModel
    }

    /// Barrier: a delete of activity 43 on a second ViewModel sharing the same repository.
    /// A delete another ViewModel had already started reaches the repository first.
    private func deleteBarrier(sharing repository: FakeActivityHistoryRepository) async {
        let barrier = await loadedViewModel(activityId: 43, repository: repository)
        var barrierOnDeletedCallCount = 0
        barrier.onDeleteConfirmed { barrierOnDeletedCallCount += 1 }
        await waitUntil { barrierOnDeletedCallCount > 0 }
        await Task.yield()
    }
}
