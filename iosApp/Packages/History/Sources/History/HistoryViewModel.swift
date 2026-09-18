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

    public var isEmpty: Bool {
        activities.isEmpty && !isLoading
    }

    private let activityHistoryRepository: ActivityHistoryRepository

    public init(activityHistoryRepository: ActivityHistoryRepository = KoinHelper().getActivityHistoryRepository()) {
        self.activityHistoryRepository = activityHistoryRepository
    }

    public func observe() async {
        for await activities in activityHistoryRepository.observeActivities() {
            self.activities = activities
            self.isLoading = false
        }
    }

    public func onDeleteActivity(_ activity: ActivityRecord) {
        Task {
            try? await activityHistoryRepository.deleteActivity(id: activity.id)
            deleteSnapshotFile(forStoredPath: activity.snapshotFilePath)
        }
    }
}
