//
//  HistoryViewModelFailureTests.swift
//  HistoryTests
//

import History
import SharedKit
import TestSupport
import XCTest

@MainActor
final class HistoryViewModelFailureTests: XCTestCase {

    private let generalErrorMessage = "Something went wrong. Please try again."

    func test_observe_failingFlow_showsErrorAndStopsLoading() async {
        let viewModel = HistoryViewModel.subject(
            repository: FakeActivityHistoryRepository(isObserveFailing: true)
        )

        await viewModel.observe()

        XCTAssertEqual(viewModel.errorMessage, generalErrorMessage)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.activities.isEmpty)
    }

    func test_observe_flowFailingAfterList_keepsLastListAndShowsError() async {
        let viewModel = HistoryViewModel.subject(
            repository: FakeActivityHistoryRepository(
                emissions: [[.fixture(id: 1)], [.fixture(id: 1), .fixture(id: 2)]],
                isObserveFailing: true
            )
        )

        await viewModel.observe()

        XCTAssertEqual(viewModel.activities.map(\.id), [1, 2])
        XCTAssertEqual(viewModel.errorMessage, generalErrorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }

    func test_onDeleteActivity_failedDelete_keepsSnapshotAndShowsError() async {
        let activity = ActivityRecord.fixture(id: 7, snapshotFilePath: "/stored/snapshot-7.png")
        let repository = FakeActivityHistoryRepository(activities: [activity])
        repository.setFailing(true)
        let deleter = FakeSnapshotFileDeleter()
        let viewModel = HistoryViewModel.subject(repository: repository, snapshotFileDeleter: deleter)

        viewModel.onDeleteActivity(activity)

        await waitUntil { viewModel.errorMessage != nil }
        await Task.yield()
        XCTAssertEqual(viewModel.errorMessage, generalErrorMessage)
        XCTAssertTrue(deleter.storedPaths.isEmpty)
        XCTAssertTrue(repository.deletedIds.isEmpty)

        viewModel.onErrorDismissed()
        XCTAssertNil(viewModel.errorMessage)
    }
}
