//
//  TrackingViewModelRouteCompletionTests.swift
//  TrackingTests
//
//  The route's end is the manager's rule: these tests drive a real TrackingViewModel with no View, and
//  read what it publishes (`routeProgress`, `canFinish`) and what the session did on its own.
//

import SharedKit
import TestSupport
@testable import Tracking
import XCTest

@MainActor
final class TrackingViewModelRouteCompletionTests: TrackingTestCase {

    /// A fix on the plan's last point (the plan is a closed loop, so it is also the start).
    private static let endUpdate: any LocationUpdate = LocationUpdateSuccess(
        coordinates: TrackingFixtures.startPoint,
        speedMetersPerSecond: nil,
        accuracyMeters: KotlinFloat(value: 5)
    )

    func test_routeProgress_followsTheFixes() async {
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates)
        let viewModel = subject.viewModel
        XCTAssertNil(viewModel.routeProgress, "No fix yet")

        viewModel.onStartClicked()

        await waitUntil { viewModel.routeProgress != nil }
        XCTAssertEqual(viewModel.routeProgress, subject.trackingSessionManager.routeProgress.value)
        XCTAssertFalse(viewModel.routeProgress?.traveledSegment.isEmpty ?? true)
    }

    func test_reachingTheRouteEnd_finishesTheSessionWithoutAView() async {
        let subject = makeSubject(updates: [TrackingFixtures.movingUpdates[0], Self.endUpdate])
        let viewModel = subject.viewModel

        viewModel.onStartClicked()

        await waitUntil { viewModel.trackingState is TrackingStateFinished }
        await waitUntil { !subject.liveActivityClient.endCalls.isEmpty }
        await Task.yield()
        XCTAssertTrue(viewModel.canFinish)
        XCTAssertEqual(subject.serviceLauncher.stopCount, 1)
        XCTAssertEqual(subject.liveActivityClient.endCalls.count, 1, "The Live Activity ends once")
    }

    func test_atTheRouteEnd_whilePaused_doesNotFinishUntilResume() async {
        let locationRepository = ChangingLocationRepository(
            location: TrackingFixtures.startPoint,
            updates: [TrackingFixtures.movingUpdates[0]]
        )
        let subject = makeSubject(changingLocationRepository: locationRepository)
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == 2 }
        viewModel.onPauseClicked()
        await waitUntil { viewModel.trackingState is TrackingStatePaused }
        locationRepository.setUpdates([Self.endUpdate])
        await Task.yield()
        XCTAssertTrue(viewModel.trackingState is TrackingStatePaused, "A paused session does not end by itself")
        XCTAssertEqual(subject.serviceLauncher.stopCount, 0)

        viewModel.onResumeClicked()

        await waitUntil { viewModel.trackingState is TrackingStateFinished }
        XCTAssertTrue(viewModel.canFinish)
        XCTAssertEqual(subject.serviceLauncher.stopCount, 1)
    }

    func test_anEmptyPlan_neverFinishes() async {
        let subject = makeSubject(
            updates: [TrackingFixtures.movingUpdates[0], Self.endUpdate],
            plannedRoutePoints: []
        )
        let viewModel = subject.viewModel

        viewModel.onStartClicked()

        await waitUntil { viewModel.currentPath.count == 3 }
        await Task.yield()
        XCTAssertTrue(viewModel.trackingState is TrackingStateTracking)
        XCTAssertFalse(viewModel.canFinish)
        XCTAssertNil(viewModel.routeProgress, "Without a plan there is no progress")
        XCTAssertEqual(subject.serviceLauncher.stopCount, 0)
    }

    func test_theFinishCard_followsCanFinish() async {
        let subject = makeSubject(updates: [TrackingFixtures.movingUpdates[0], Self.endUpdate])
        let viewModel = subject.viewModel
        XCTAssertFalse(viewModel.canFinish, "Idle")

        viewModel.onStartClicked()

        await waitUntil { viewModel.trackingState is TrackingStateFinished }
        XCTAssertTrue(viewModel.canFinish, "The route's end shows the finish card")

        viewModel.onDiscardClicked()

        XCTAssertFalse(viewModel.canFinish, "A discarded session shows no finish card")
    }
}
