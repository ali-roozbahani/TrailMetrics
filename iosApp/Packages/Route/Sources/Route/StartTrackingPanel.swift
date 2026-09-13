//
//  StartTrackingPanel.swift
//  Route
//

import SharedKit
import SwiftUI

struct StartTrackingPanel: View {
    let selectedActivityType: ActivityType
    let onActivityTypeSelected: (ActivityType) -> Void
    let onResetClicked: () -> Void
    let onStartTrackingClicked: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Picker(
                "Activity",
                selection: Binding(get: { selectedActivityType }, set: onActivityTypeSelected)
            ) {
                ForEach(ActivityType.allCases, id: \.self) { activityType in
                    Text(activityType.displayName).tag(activityType)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button("Reset", action: onResetClicked)
                    .buttonStyle(.bordered)
                Button("Start Tracking", action: onStartTrackingClicked)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
}
