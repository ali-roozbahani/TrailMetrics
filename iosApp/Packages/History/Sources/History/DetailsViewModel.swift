//
//  DetailsViewModel.swift
//  History
//

import Foundation
import SharedKit

@MainActor
public class DetailsViewModel: ObservableObject {
    @Published public var activity: ActivityRecord?
    @Published public var isLoading = true
    @Published public private(set) var errorMessage: String?

    private let activityId: Int64
    private let activityHistoryRepository: ActivityHistoryRepository
    // Set synchronously before the delete `Task` starts, so a second confirmation that
    // arrives while the first delete is in flight is ignored (as Android's
    // `DetailsViewModel.isDeleteStarted`). Cleared when the delete fails, to allow a retry.
    private var isDeleteStarted = false

    public init(
        activityId: Int64,
        activityHistoryRepository: ActivityHistoryRepository = KoinHelper().getActivityHistoryRepository()
    ) {
        self.activityId = activityId
        self.activityHistoryRepository = activityHistoryRepository

        Task {
            do {
                activity = try await activityHistoryRepository.getActivity(id: activityId)
            } catch {
                errorMessage = HistoryErrorMessage.general
            }
            isLoading = false
        }
    }

    /// Deletes the activity, then its snapshot file, then calls `onDeleted` once. A failed
    /// delete keeps both, shows an error and does not call `onDeleted`.
    public func onDeleteConfirmed(onDeleted: @escaping () -> Void) {
        guard !isDeleteStarted else { return }
        isDeleteStarted = true
        Task {
            do {
                try await activityHistoryRepository.deleteActivity(id: activityId)
            } catch {
                isDeleteStarted = false
                errorMessage = HistoryErrorMessage.general
                return
            }
            deleteSnapshotFile(forStoredPath: activity?.snapshotFilePath)
            onDeleted()
        }
    }

    public func onErrorDismissed() {
        errorMessage = nil
    }
}
