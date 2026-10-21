//
//  RouteMapUnavailableView.swift
//  Route
//

import SwiftUI

/// Shown on the Route tab instead of the map when the build has no Google Maps key.
struct RouteMapUnavailableView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "map")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("map_unavailable_message", bundle: .module)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    RouteMapUnavailableView()
}
