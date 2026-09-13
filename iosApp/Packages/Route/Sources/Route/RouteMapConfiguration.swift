//
//  RouteMapConfiguration.swift
//  Route
//

import GoogleMaps

/// Composition-root entry point for the Google Maps SDK. Keeps `import GoogleMaps` confined to
/// this package so the app target never needs GoogleMaps as a direct dependency.
public enum RouteMapConfiguration {
    public static func configure(apiKey: String) {
        GMSServices.provideAPIKey(apiKey)
    }
}
