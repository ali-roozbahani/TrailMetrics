//
//  ActivityType+LiveActivity.swift
//  Tracking
//

import SharedKit

extension ActivityType {
    // Not shown from here: the Live Activity attribute carries this English name as a stable key,
    // and the widget extension localizes it with its own catalog (TrackingLiveActivity.swift).
    var liveActivityKey: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        }
    }
}
