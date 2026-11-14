//
//  HistoryViewModel+Subject.swift
//  HistoryTests
//

import History
import SharedKit
import TestSupport

extension HistoryViewModel {
    /// A ViewModel whose every dependency is backed by `repository`.
    static func subject(
        repository: FakeActivityHistoryRepository,
        snapshotFileDeleter: SnapshotFileDeleting = FakeSnapshotFileDeleter()
    ) -> HistoryViewModel {
        HistoryViewModel(
            activityHistoryRepository: repository,
            observeActivitiesUseCase: ObserveActivitiesUseCase(activityHistoryRepository: repository),
            snapshotFileDeleter: snapshotFileDeleter
        )
    }
}
