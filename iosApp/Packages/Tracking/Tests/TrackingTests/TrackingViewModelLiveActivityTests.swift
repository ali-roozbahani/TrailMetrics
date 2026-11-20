//
//  TrackingViewModelLiveActivityTests.swift
//  TrackingTests
//
//  What the ViewModel hands the Live Activity controller, on a fake ActivityKit client: that Pause reaches
//  the Activity as a held timer, and Resume as a running one.
//

import SharedKit
import TestSupport
import XCTest

@MainActor
final class TrackingViewModelLiveActivityTests: TrackingTestCase {

    func test_onPauseClicked_sendsAHeldTimerToTheLiveActivity() async {
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates)
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }
        await waitUntil { subject.liveActivityClient.updates.contains { $0.state.pausedAt == nil } }

        viewModel.onPauseClicked()

        await waitUntil { viewModel.trackingState is TrackingStatePaused }
        await waitUntil { subject.liveActivityClient.updates.last?.state.pausedAt != nil }
        XCTAssertNil(subject.liveActivityClient.updates.last?.staleDate, "A paused session sends no updates")
    }

    func test_onResumeClicked_sendsARunningTimerAgain() async {
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates)
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }
        viewModel.onPauseClicked()
        await waitUntil { subject.liveActivityClient.updates.last?.state.pausedAt != nil }

        viewModel.onResumeClicked()

        await waitUntil { viewModel.trackingState is TrackingStateTracking }
        await waitUntil { subject.liveActivityClient.updates.last?.state.pausedAt == nil }
        XCTAssertNotNil(subject.liveActivityClient.updates.last?.staleDate)
    }

    func test_sessionFinishedByTheManager_endsTheLiveActivityOnce() async {
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates)
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }

        subject.trackingSessionManager.stop()

        await waitUntil { viewModel.trackingState is TrackingStateFinished }
        await waitUntil { !subject.liveActivityClient.endCalls.isEmpty }
        let ends = subject.liveActivityClient.endCalls
        XCTAssertEqual(ends.count, 1, "The Live Activity ends once")
        XCTAssertNotNil(ends.first?.finalState, "It ends with the final totals")
        XCTAssertGreaterThan(ends.first?.finalState?.distanceMeters ?? 0, 0)
    }

    func test_onStopClicked_endsTheLiveActivityOnce() async {
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates)
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }

        viewModel.onStopClicked()

        await waitUntil { !subject.liveActivityClient.endCalls.isEmpty }
        await Task.yield()
        XCTAssertEqual(subject.liveActivityClient.endCalls.count, 1)
    }
}
