//
//  LocationPermissionRequester.swift
//  Route
//

import CoreLocation

@MainActor
final class LocationPermissionRequester: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    private var onGranted: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func request(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
        manager.requestWhenInUseAuthorization()
    }
}

extension LocationPermissionRequester: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                let callback = onGranted
                onGranted = nil
                callback?()
            default:
                break
            }
        }
    }
}
