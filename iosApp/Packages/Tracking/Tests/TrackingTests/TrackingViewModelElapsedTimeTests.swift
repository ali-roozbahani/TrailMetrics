//
//  TrackingViewModelElapsedTimeTests.swift
//  TrackingTests
//
//  The elapsed time the metrics panel shows moves between location events while Tracking and stands still
//  while Paused. No location event is delivered: only the ViewModel's monotonic clock moves, and the shown time
//  is computed when read (the panel reads it once a second while on screen).
//

import SharedKit
import TestSupport
import Tracking
import XCTest

@MainActor
final class TrackingViewModelElapsedTimeTests: TrackingTestCase {

    /// The manager's monotonic reading at the last accounted update: the base of the shown time.
    private func lastUpdate(of viewModel: TrackingViewModel) -> Int64? {
        viewModel.currentMetrics?.lastUpdateElapsedRealtimeMillis
    }

    func test_whileTracking_theShownTimeAdvancesWithoutLocationEvents() async throws {
        let subject = makeSubject()
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.trackingState is TrackingStateTracking }
        let base = try XCTUnwrap(lastUpdate(of: viewModel))

        subject.clock.setElapsedRealtimeMillis(base + 1_500)
        await waitUntil { viewModel.displayedElapsedMillis == 1_500 }

        subject.clock.setElapsedRealtimeMillis(base + 2_500)
        await waitUntil { viewModel.displayedElapsedMillis == 2_500 }

        XCTAssertTrue(viewModel.trackingState is TrackingStateTracking)
        XCTAssertEqual(viewModel.currentMetrics?.elapsedMillis, 0, "The recorded time waits for a location event")
    }

    func test_whilePaused_theShownTimeStandsStill() async throws {
        let subject = makeSubject()
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.trackingState is TrackingStateTracking }
        viewModel.onPauseClicked()
        await waitUntil { viewModel.trackingState is TrackingStatePaused }
        let recorded = try XCTUnwrap(viewModel.currentMetrics?.elapsedMillis)
        let base = try XCTUnwrap(lastUpdate(of: viewModel))
        XCTAssertEqual(viewModel.displayedElapsedMillis, recorded)

        subject.clock.setElapsedRealtimeMillis(base + 10_000)

        XCTAssertEqual(viewModel.displayedElapsedMillis, recorded)
    }

    func test_whenFinished_theShownTimeIsTheFinalTimeAndStandsStill() async throws {
        let subject = makeSubject()
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.trackingState is TrackingStateTracking }
        // Ended by the manager, as at the route's end, so the ViewModel keeps observing it.
        subject.trackingSessionManager.stop()
        await waitUntil { viewModel.trackingState is TrackingStateFinished }
        let recorded = try XCTUnwrap(viewModel.currentMetrics?.elapsedMillis)
        let base = try XCTUnwrap(lastUpdate(of: viewModel))
        XCTAssertEqual(viewModel.displayedElapsedMillis, recorded)

        subject.clock.setElapsedRealtimeMillis(base + 10_000)

        XCTAssertEqual(viewModel.displayedElapsedMillis, recorded)
    }

    func test_afterResume_theShownTimeGoesOnFromThePausedTime() async throws {
        let subject = makeSubject()
        let viewModel = subject.viewModel
        viewModel.onStartClicked()
        await waitUntil { viewModel.trackingState is TrackingStateTracking }
        viewModel.onPauseClicked()
        await waitUntil { viewModel.trackingState is TrackingStatePaused }
        let recorded = try XCTUnwrap(viewModel.currentMetrics?.elapsedMillis)

        viewModel.onResumeClicked()
        await waitUntil { viewModel.trackingState is TrackingStateTracking }
        // Resume set the last update to the resume time: the pause is not counted.
        let resumedAt = try XCTUnwrap(lastUpdate(of: viewModel))
        subject.clock.setElapsedRealtimeMillis(resumedAt + 1_000)

        await waitUntil { viewModel.displayedElapsedMillis == recorded + 1_000 }
    }
}
