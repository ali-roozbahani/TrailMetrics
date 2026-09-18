//
//  HistoryMetricCell.swift
//  History
//

import SwiftUI

/// Mirrors `Tracking`'s private `TrackingMetricCell` layout (icon + label + value), shared
/// here between the History row and Details screen rather than duplicated between them.
struct HistoryMetricCell: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
