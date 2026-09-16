//
//  TrackingUiEvent.swift
//  Tracking
//

import SharedKit

/// Mirrors Android's `TrackingUiEvent`, minus `RequestLocationPermission`: on iOS,
/// `IosLocationRepositoryImpl.observeLocationUpdates()` already asks for and awaits
/// permission internally before starting updates, so there's no separate Swift-side
/// permission-retry event to drive (same reasoning `Route`'s iOS `RouteUiEvent` already
/// applied — Android's equivalent permission-request event has no iOS counterpart there).
public enum TrackingUiEvent {
    case showError(any RouteUiError)

    // Emitted only when a stop is triggered from outside the View itself —
    // currently just the Live Activity's Stop button, relayed through
    // TrackingViewModel.handleStopNotification(). The in-app Stop button
    // (TrackingView's own controlsRow/exit alert) already calls `dismiss()`
    // directly at its call site and never emits this.
    case dismissed
}
