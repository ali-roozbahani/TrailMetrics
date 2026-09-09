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

    private let repository: ActivityHistoryRepository

    public init(repository: ActivityHistoryRepository = KoinHelper().getActivityHistoryRepository()) {
        self.repository = repository
    }

    public func observe() async {
        for await list in repository.observeActivities() {
            self.activities = list
            self.isLoading = false
        }
    }
}
