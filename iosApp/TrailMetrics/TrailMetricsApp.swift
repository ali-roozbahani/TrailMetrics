//
//  TrailMetricsApp.swift
//  TrailMetrics
//
//  Created by Ali Roozbahani on 07.09.26.
//

import Route
import SharedKit
import SwiftUI

@main
struct TrailMetricsApp: App {

    init() {
        KoinInitIosKt.doInitKoinIos()

        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !apiKey.isEmpty {
            RouteMapConfiguration.configure(apiKey: apiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
