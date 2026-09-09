//
//  TrailMetricsApp.swift
//  TrailMetrics
//
//  Created by Ali Roozbahani on 07.09.26.
//

import SwiftUI
import SharedKit

@main
struct TrailMetricsApp: App {
    
    init () {
        KoinInitIosKt.doInitKoinIos()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
