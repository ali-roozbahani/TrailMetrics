//
//  RouteUiEvent.swift
//  Route
//

import SharedKit

public enum RouteUiEvent {
    case showError(any RouteUiError)
    /// The directions call got no response (`RouteUiErrorNoConnection`): shown with a Retry that generates again.
    case showNoConnection
    case requestUserProfile
    case navigateToTracking(startPoint: Coordinates, plannedRoutePoints: [Coordinates], activityType: ActivityType)
}
