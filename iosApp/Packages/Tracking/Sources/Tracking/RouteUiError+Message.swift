//
//  RouteUiError+Message.swift
//  Tracking
//

import SharedKit

extension RouteUiError {
    var message: String {
        switch onEnum(of: self) {
        case .general:
            return "Something went wrong. Please try again."
        case .locationUnavailable:
            return "Unable to determine your current location."
        case .missingLocationPermission:
            return "Location permission is required to track this activity."
        }
    }
}
