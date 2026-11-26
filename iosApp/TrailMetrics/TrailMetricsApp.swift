//
//  TrailMetricsApp.swift
//  TrailMetrics
//
//  Created by Ali Roozbahani on 07.09.26.
//

import os
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
        let signposter = StartupSignposts.signposter
        // First, so an uncaught Kotlin exception during the Koin start is reported too (off without the config file).
        signposter.withIntervalSignpost("CrashReportingStart") {
            CrashReporting.startIfConfigured()
        }

        #if UITEST_SEAM
        // Debug-UITest only (the test-only framework variant): a UI test's scenario replaces the
        // production bindings with in-memory fakes; without the argument the app starts as usual.
        if let scenario = UITestScenarioArgument.scenario() {
            uiTestControls = doInitKoinIosForUiTest(scenario: scenario)
            UIView.setAnimationsEnabled(false)
        } else {
            uiTestControls = nil
            signposter.withIntervalSignpost("KoinStart") {
                KoinInitIosKt.doInitKoinIos()
            }
        }
        #else
        signposter.withIntervalSignpost("KoinStart") {
            KoinInitIosKt.doInitKoinIos()
        }
        #endif

        signposter.withIntervalSignpost("MapsConfigure") {
            RouteMapConfiguration.configureIfKeyPresent()
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
