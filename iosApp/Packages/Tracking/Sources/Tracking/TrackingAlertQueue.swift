//
//  TrackingAlertQueue.swift
//  Tracking
//

/// One alert of the Tracking screen's error alert.
enum TrackingAlert: Equatable {
    /// An error message (`RouteUiError.message`).
    case error(String)
    /// The unsaved-session warning; its OK marks the warning shown.
    case sessionNotSaved
}

/// The alerts TrackingView shows through its one error alert, in order. One alert and not two: SwiftUI does not
/// present a second `.alert` while another is up, so a warning that arrived behind an error alert would never show
/// (owner decision of 2026-11-26: the warning is never lost behind an error alert).
///
/// - The warning is queued once and nothing replaces it: it waits behind the alert on screen and shows after its OK.
/// - Errors keep their behavior: at most one error is kept, and a newer error replaces the older one in its place.
struct TrackingAlertQueue {
    private(set) var alerts: [TrackingAlert] = []

    /// The alert on screen: the oldest one kept.
    var current: TrackingAlert? { alerts.first }

    mutating func enqueue(_ alert: TrackingAlert) {
        switch alert {
        case .sessionNotSaved:
            if !alerts.contains(.sessionNotSaved) { alerts.append(alert) }
        case .error:
            if let index = alerts.firstIndex(where: \.isError) {
                alerts[index] = alert
            } else {
                alerts.append(alert)
            }
        }
    }

    /// The OK of `alert`: removes it when it is still the one on screen, so a second call for the same OK, or a call
    /// for an alert a newer error already replaced, removes nothing. Returns whether it removed it.
    @discardableResult
    mutating func dismiss(_ alert: TrackingAlert) -> Bool {
        guard current == alert else { return false }
        alerts.removeFirst()
        return true
    }
}

private extension TrackingAlert {
    var isError: Bool {
        guard case .error = self else { return false }
        return true
    }
}
