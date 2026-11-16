//
//  TrackingActivityAttributes.swift
//  Tracking
//
//  Canonical copy. A byte-identical twin lives at
//  iosApp/TrackingWidget/TrackingActivityAttributes.swift for the widget
//  extension target, which must not link this package (it depends on
//  SharedKit/the Kotlin runtime, which the extension process should not
//  load). Swift Package Manager targets have no visibility into loose
//  files owned by the host Xcode project, so the usual "one shared file,
//  dual target membership" pattern for ActivityAttributes can't cross an
//  SPM package boundary — keep both copies in sync when editing either.
//

import ActivityKit
import Foundation

public struct TrackingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var distanceMeters: Double
        public var currentSpeedMetersPerSecond: Double?
        /// The elapsed time is drawn by the system from this date, with no update needed: the date the
        /// timer would have started at had it never been paused (now minus the elapsed time).
        public var timerStart: Date
        /// Set while the session is paused: the timer shows the time as of this date and does not advance.
        public var pausedAt: Date?

        public init(
            distanceMeters: Double,
            currentSpeedMetersPerSecond: Double?,
            timerStart: Date,
            pausedAt: Date?
        ) {
            self.distanceMeters = distanceMeters
            self.currentSpeedMetersPerSecond = currentSpeedMetersPerSecond
            self.timerStart = timerStart
            self.pausedAt = pausedAt
        }
    }

    public var activityType: String

    public init(activityType: String) {
        self.activityType = activityType
    }
}

public enum TrackingLiveActivityConstants {
    public static let stopNotificationName = "dev.roozbahani.TrailMetrics.stopTrackingRequested"
    public static let urlScheme = "trailmetrics"
    public static let trackingHost = "tracking"
    public static let appGroupIdentifier = "group.dev.roozbahani.TrailMetrics"

    public static var deepLinkURL: URL {
        guard let url = URL(string: "\(urlScheme)://\(trackingHost)") else {
            preconditionFailure("Static tracking deep link URL must always be valid")
        }
        return url
    }
}
