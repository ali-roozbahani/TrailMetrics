//
//  RouteUiError+Message.swift
//  Tracking
//

import Foundation
import SharedKit

extension RouteUiError {
    var message: String {
        switch onEnum(of: self) {
        case .general:
            return String(localized: "general_error_message", bundle: .module)
        case .locationUnavailable:
            return String(localized: "Unable to determine your current location.", bundle: .module)
        case .missingLocationPermission:
            return String(localized: "Location permission is required to track this activity.", bundle: .module)
        }
    }
}
