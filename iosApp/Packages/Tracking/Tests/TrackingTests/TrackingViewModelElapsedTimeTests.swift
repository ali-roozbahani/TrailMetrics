//
//  TrackingViewModelElapsedTimeTests.swift
//  TrackingTests
//
//  The elapsed time the metrics panel shows ticks between location events while Tracking and stands still
//  while Paused. No location event is delivered: only the ViewModel's monotonic clock moves, and the ticks
//  (at each full second of the shown time) are real ones, so each wait is at most about a second.
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
        // Longer than one tick: a running ticker would have shown the new reading by now.
        try await Task.sleep(for: .milliseconds(1_200))

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
