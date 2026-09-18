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

    private let activityId: Int64
    private let activityHistoryRepository: ActivityHistoryRepository

    public init(
        activityId: Int64,
        activityHistoryRepository: ActivityHistoryRepository = KoinHelper().getActivityHistoryRepository()
    ) {
        self.activityId = activityId
        self.activityHistoryRepository = activityHistoryRepository

        Task {
            activity = try? await activityHistoryRepository.getActivity(id: activityId)
            isLoading = false
        }
    }
}
