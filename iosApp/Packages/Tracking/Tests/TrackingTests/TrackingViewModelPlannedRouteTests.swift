//
//  TrackingViewModelPlannedRouteTests.swift
//  TrackingTests
//
//  The plan a TrackingViewModel was opened with is kept with the session it starts, so a session offered
//  after a restart shows its planned route again (Android's TrackingViewModelPlannedRouteTest).
//

import SharedKit
import TestSupport
@testable import Tracking
import XCTest

@MainActor
final class TrackingViewModelPlannedRouteTests: TrackingTestCase {

    func test_onStartClicked_keepsThePlannedRouteInTheSessionDetails() async {
        let subject = makeSubject()

        subject.viewModel.onStartClicked()

        await waitUntil { subject.viewModel.trackingState is TrackingStateTracking }
        XCTAssertEqual(
            subject.trackingSessionManager.sessionDetails.value?.plannedRoute,
            TrackingFixtures.plannedRoutePoints
        )
    }

    func test_onStartClicked_storesThePlannedRouteWithTheSession() async {
        let subject = makeSubject()

        subject.viewModel.onStartClicked()

        await waitUntil { subject.sessionStore.storedSession?.plannedRoute == TrackingFixtures.plannedRoutePoints }
        XCTAssertEqual(subject.sessionStore.storedSession?.plannedRoute, TrackingFixtures.plannedRoutePoints)
    }
}
