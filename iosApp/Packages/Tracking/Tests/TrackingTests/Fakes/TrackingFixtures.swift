//
//  TrackingFixtures.swift
//  TrackingTests
//

import SharedKit

enum TrackingFixtures {
    static let startPoint = Coordinates(latitude: 52.37, longitude: 4.89)

    static let plannedRoutePoints = [
        startPoint,
        Coordinates(latitude: 52.38, longitude: 4.90),
        startPoint
    ]

    /// Two fixes roughly 110 m apart each, heading north from `startPoint`.
    static let movingUpdates: [any LocationUpdate] = [
        LocationUpdateSuccess(
            coordinates: Coordinates(latitude: 52.371, longitude: 4.89),
            speedMetersPerSecond: nil,
            accuracyMeters: KotlinFloat(value: 5)
        ),
        LocationUpdateSuccess(
            coordinates: Coordinates(latitude: 52.372, longitude: 4.89),
            speedMetersPerSecond: nil,
            accuracyMeters: KotlinFloat(value: 5)
        )
    ]

    static let movingPath = [
        startPoint,
        Coordinates(latitude: 52.371, longitude: 4.89),
        Coordinates(latitude: 52.372, longitude: 4.89)
    ]
}

extension TrackingFixtures {
    static func metrics(path: [Coordinates]) -> TrackingMetrics {
        TrackingMetrics(
            elapsedMillis: 60_000,
            lastUpdateElapsedRealtimeMillis: 60_000,
            distanceMeters: 220,
            path: path,
            currentSpeedMetersPerSecond: nil
        )
    }

    /// A stored session as the store returns it after the app was terminated.
    static func storedSession(
        _ state: TrackingState,
        activityType: ActivityType? = .cycling,
        startedAtEpochMillis: Int64 = 1_699_999_000_000
    ) -> StoredTrackingSession {
        StoredTrackingSession(
            state: state,
            activityType: activityType,
            startedAtEpochMillis: KotlinLong(value: startedAtEpochMillis)
        )
    }
}
