//
//  HistoryViewModel.swift
//  History
//
//  Created by Ali Roozbahani on 09.09.26.
//

import Foundation
import SharedKit

@MainActor
public class HistoryViewModel: ObservableObject {
    @Published public var activities: [ActivityRecord] = []
    @Published public var isLoading = true
    @Published public private(set) var errorMessage: String?

    public var isEmpty: Bool {
        activities.isEmpty && !isLoading
    }

    private let activityHistoryRepository: ActivityHistoryRepository
    private let observeActivitiesUseCase: ObserveActivitiesUseCase
    private let snapshotFileDeleter: SnapshotFileDeleter

    public init(
        activityHistoryRepository: ActivityHistoryRepository = KoinHelper().getActivityHistoryRepository(),
        observeActivitiesUseCase: ObserveActivitiesUseCase = KoinHelper().observeActivitiesUseCase(),
        snapshotFileDeleter: SnapshotFileDeleter = KoinHelper().snapshotFileDeleter()
    ) {
        self.activityHistoryRepository = activityHistoryRepository
        self.observeActivitiesUseCase = observeActivitiesUseCase
        self.snapshotFileDeleter = snapshotFileDeleter
    }

    /// Observes through `ObserveActivitiesUseCase`, not the repository's Flow directly: SKIE
    /// terminates the app when a Flow fails, and the use case turns that failure into
    /// `Failed` on the Kotlin side. After `Failed` the flow completes and the last list stays.
    public func observe() async {
        for await update in observeActivitiesUseCase.invoke() {
            await MainActor.run {
                switch onEnum(of: update) {
                case .loaded(let loaded):
                    activities = loaded.activities
                case .failed:
                    errorMessage = HistoryErrorMessage.general
                }
                isLoading = false
            }
        }
    }

    /// Deletes the record, then its snapshot file. A failed delete keeps both and shows an error.
    public func onDeleteActivity(_ activity: ActivityRecord) {
        Task {
            do {
                try await activityHistoryRepository.deleteActivity(id: activity.id)
            } catch {
                errorMessage = HistoryErrorMessage.general
                return
            }
            await snapshotFileDeleter.deleteBestEffort(storedPath: activity.snapshotFilePath)
        }
    }

    /// The image file of the activity's snapshot, resolved by the same Kotlin rule that deletes it.
    public func snapshotURL(for activity: ActivityRecord) -> URL? {
        snapshotFileDeleter.snapshotURL(forStoredPath: activity.snapshotFilePath)
    }

    public func onErrorDismissed() {
        errorMessage = nil
    }
}
