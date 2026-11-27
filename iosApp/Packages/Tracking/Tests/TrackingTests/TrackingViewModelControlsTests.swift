//
//  TrackingViewModelControlsTests.swift
//  TrackingTests
//
//  The ViewModel only shows the controls `domain` says are available (`availableControls`, the rules
//  Android asks too).
//

import SharedKit
import TestSupport
import Tracking
import XCTest

@MainActor
final class TrackingViewModelControlsTests: TrackingTestCase {

    func test_controls_areExactlyWhatDomainSaysInEveryState() async {
        let subject = makeSubject(updates: TrackingFixtures.movingUpdates)
        let viewModel = subject.viewModel
        func assertMatchesDomain(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
            let expected = viewModel.trackingState.availableControls(isRestoring: false)
            XCTAssertEqual(viewModel.canStart, expected.canStart, "canStart in \(label)", file: file, line: line)
            XCTAssertEqual(viewModel.canPause, expected.canPause, "canPause in \(label)", file: file, line: line)
            XCTAssertEqual(viewModel.canResume, expected.canResume, "canResume in \(label)", file: file, line: line)
            XCTAssertEqual(viewModel.canStop, expected.canStop, "canStop in \(label)", file: file, line: line)
            XCTAssertEqual(viewModel.canFinish, expected.canSave, "canFinish in \(label)", file: file, line: line)
            XCTAssertEqual(
                viewModel.canDiscardFinished, expected.canDiscard, "canDiscard in \(label)", file: file, line: line
            )
        }

        assertMatchesDomain("idle")
        viewModel.onStartClicked()
        await waitUntil { viewModel.currentPath.count == TrackingFixtures.movingPath.count }
        assertMatchesDomain("tracking")
        viewModel.onPauseClicked()
        await waitUntil { viewModel.trackingState is TrackingStatePaused }
        assertMatchesDomain("paused")
        viewModel.onStopClicked()
        assertMatchesDomain("finished")
    }

    func test_controls_whileRestoring_offerNoStartAndTheRestAsDomainSays() {
        let viewModel = makeSubject(isRestoring: true).viewModel

        let expected = viewModel.trackingState.availableControls(isRestoring: true)

        XCTAssertFalse(viewModel.canStart)
        XCTAssertEqual(viewModel.canStart, expected.canStart)
        XCTAssertEqual(viewModel.canStop, expected.canStop)
    }
}
