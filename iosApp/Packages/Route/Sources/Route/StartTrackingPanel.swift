//
//  StartTrackingPanel.swift
//  Route
//

import DesignSystem
import SharedKit
import SwiftUI

struct StartTrackingPanel: View {
    let selectedActivityType: ActivityType
    let onActivityTypeSelected: (ActivityType) -> Void
    let onResetClicked: () -> Void
    let onStartTrackingClicked: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ActivityTypeControl(
                selectedActivityType: selectedActivityType,
                onActivityTypeSelected: onActivityTypeSelected
            )

            HStack(spacing: 12) {
                Button(action: onResetClicked) {
                    Label("Reset", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(.trailGreen)
                Button("Start Tracking", action: onStartTrackingClicked)
                    .buttonStyle(.borderedProminent)
                    .tint(.trailGreen)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Replaces a segmented `Picker` here: `Label(_, systemImage:)` doesn't render its icon
/// inside a segmented-style `Picker` on the tested iOS version, so this hand-rolled
/// equivalent shows an icon and text per `ActivityType`, highlighting the selection.
private struct ActivityTypeControl: View {
    let selectedActivityType: ActivityType
    let onActivityTypeSelected: (ActivityType) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ActivityType.allCases, id: \.self) { activityType in
                segment(for: activityType)
            }
        }
        .padding(4)
        .background(Color(.systemFill), in: RoundedRectangle(cornerRadius: 10))
    }

    private func segment(for activityType: ActivityType) -> some View {
        let isSelected = activityType == selectedActivityType
        return Button {
            onActivityTypeSelected(activityType)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: activityType.symbolName)
                Text(activityType.displayName)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                isSelected ? Color.trailGreen : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }
}

private extension ActivityType {
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        }
    }

    var symbolName: String {
        switch self {
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .walking: return "figure.walk"
        }
    }
}
