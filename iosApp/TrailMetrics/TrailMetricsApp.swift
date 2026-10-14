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
    #if UITEST_SEAM
    // Set when a UI test launched the app with `-uiTestScenario <name>`; read by the probe.
    private let uiTestControls: UiTestControls?
    #endif

    init() {
        #if UITEST_SEAM
        // Debug-UITest only (the test-only framework variant): a UI test's scenario replaces the
        // production bindings with in-memory fakes; without the argument the app starts as usual.
        if let scenario = UITestScenarioArgument.scenario() {
            uiTestControls = doInitKoinIosForUiTest(scenario: scenario)
            UIView.setAnimationsEnabled(false)
        } else {
            uiTestControls = nil
            KoinInitIosKt.doInitKoinIos()
        }
        #else
        KoinInitIosKt.doInitKoinIos()
        #endif

        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String, !apiKey.isEmpty {
            RouteMapConfiguration.configure(apiKey: apiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            #if UITEST_SEAM
            ContentView()
                .overlay(alignment: .top) {
                    if let uiTestControls {
                        UITestProbeView(controls: uiTestControls)
                    }
                }
            #else
            ContentView()
            #endif
        }
    }
}
