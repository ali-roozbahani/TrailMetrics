//
//  RouteMapConfiguration.swift
//  Route
//

import Foundation
import GoogleMaps

/// Composition-root entry point for the Google Maps SDK. Keeps `import GoogleMaps` confined to
/// this package so the app target never needs GoogleMaps as a direct dependency.
///
/// Whether a Maps key is present is decided here and only here: the app configures the SDK
/// through `configureIfKeyPresent()` and `RouteView` shows the map only when `isMapAvailable`,
/// both reading the same `apiKey`. Creating a `GMSMapView` without a configured SDK aborts the
/// app, so the two must never disagree.
public enum RouteMapConfiguration {
    private static let infoDictionaryKey = "GMSApiKey"

    /// The key from the app's Info.plist, or nil when it is missing or empty.
    public static var apiKey: String? {
        apiKey(from: Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey))
    }

    public static var isMapAvailable: Bool {
        apiKey != nil
    }

    /// The decision "key present or not" for a raw Info.plist value. A value that is not a
    /// string, or only whitespace, counts as no key.
    public static func apiKey(from infoValue: Any?) -> String? {
        guard let key = (infoValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    public static func configureIfKeyPresent() {
        if let apiKey {
            GMSServices.provideAPIKey(apiKey)
        }
    }
}
