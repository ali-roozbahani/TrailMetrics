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

    public init(
        activityHistoryRepository: ActivityHistoryRepository = KoinHelper().getActivityHistoryRepository(),
        observeActivitiesUseCase: ObserveActivitiesUseCase = KoinHelper().observeActivitiesUseCase()
    ) {
        self.activityHistoryRepository = activityHistoryRepository
        self.observeActivitiesUseCase = observeActivitiesUseCase
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
            deleteSnapshotFile(forStoredPath: activity.snapshotFilePath)
        }
    }

    public func onErrorDismissed() {
        errorMessage = nil
    }
}
