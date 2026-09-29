//
//  ActivityRecord+Fixture.swift
//  HistoryTests
//

import Foundation
import SharedKit

extension ActivityRecord {
    static func fixture(id: Int64, snapshotFilePath: String? = nil) -> ActivityRecord {
        ActivityRecord(
            id: id,
            activityType: .running,
            startedAtEpochMillis: 1_000,
            endedAtEpochMillis: 61_000,
            distanceMeters: 250,
            durationMillis: 60_000,
            averageSpeedMetersPerSecond: KotlinFloat(value: 4.2),
            calories: KotlinDouble(value: 18),
            plannedRoutePoints: [],
            actualPath: [],
            snapshotFilePath: snapshotFilePath
        )
    }
}
