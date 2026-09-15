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
}
