//
//  RouteMapUnavailableView.swift
//  Route
//

import SwiftUI

/// Shown on the Route tab instead of the map when the build has no Google Maps key.
struct RouteMapUnavailableView: View {
    static let message = "The map is unavailable because the Google Maps key is not configured. "
        + "Set the key in the build settings."

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(Self.message)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RouteMapUnavailableView()
}
