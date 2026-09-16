//
//  TrackingActivityAttributes.swift
//  TrackingWidgetExtension
//
//  Extension-side twin. The canonical copy lives at
//  iosApp/Packages/Tracking/Sources/Tracking/TrackingActivityAttributes.swift,
//  used by TrackingViewModel. This target can't depend on that SPM package
//  (it pulls in SharedKit/the Kotlin runtime, which this process should not
//  load), and SPM packages have no visibility into loose files owned by the
//  host Xcode project — so the usual "one shared file, dual target
//  membership" pattern for ActivityAttributes can't cross an SPM package
//  boundary here. Keep both copies byte-identical when editing either.
//

import ActivityKit
import Foundation

public struct TrackingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var distanceMeters: Double
        public var elapsedMillis: Int64
        public var currentSpeedMetersPerSecond: Double?

        public init(distanceMeters: Double, elapsedMillis: Int64, currentSpeedMetersPerSecond: Double?) {
            self.distanceMeters = distanceMeters
            self.elapsedMillis = elapsedMillis
            self.currentSpeedMetersPerSecond = currentSpeedMetersPerSecond
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
