//
//  RouteUiEvent.swift
//  Route
//

import SharedKit

public enum RouteUiEvent {
    case requestLocationPermission
    case showError(any RouteUiError)
    case requestUserProfile
    case navigateToTracking(startPoint: Coordinates, plannedRoutePoints: [Coordinates], activityType: ActivityType)
}
