//
//  TrackingAlertQueueTests.swift
//  TrackingTests
//
//  The Tracking screen's one alert: the unsaved-session warning is never lost behind an error alert that is
//  already up (owner decision of 2026-11-25), and errors keep their behavior.
//

@testable import Tracking
import XCTest

final class TrackingAlertQueueTests: XCTestCase {

    func test_warningBehindAnErrorOnScreen_isShownAfterTheErrorsOK() {
        var queue = TrackingAlertQueue()
        queue.enqueue(.error("Location unavailable"))

        queue.enqueue(.sessionNotSaved)

        XCTAssertEqual(queue.current, .error("Location unavailable"), "the error on screen stays")
        XCTAssertTrue(queue.dismiss(.error("Location unavailable")))
        XCTAssertEqual(queue.current, .sessionNotSaved, "the warning comes next")
        XCTAssertTrue(queue.dismiss(.sessionNotSaved))
        XCTAssertNil(queue.current)
    }

    func test_anErrorAfterTheWarning_doesNotReplaceIt() {
        var queue = TrackingAlertQueue()
        queue.enqueue(.sessionNotSaved)

        queue.enqueue(.error("Location unavailable"))

        XCTAssertEqual(queue.current, .sessionNotSaved)
        queue.dismiss(.sessionNotSaved)
        XCTAssertEqual(queue.current, .error("Location unavailable"))
    }

    func test_aSecondWarning_isNotQueuedTwice() {
        var queue = TrackingAlertQueue()
        queue.enqueue(.sessionNotSaved)

        queue.enqueue(.sessionNotSaved)

        XCTAssertEqual(queue.alerts, [.sessionNotSaved])
    }

    func test_aNewerError_replacesTheOlderOneInItsPlace() {
        var queue = TrackingAlertQueue()
        queue.enqueue(.error("first"))
        queue.enqueue(.sessionNotSaved)

        queue.enqueue(.error("second"))

        XCTAssertEqual(queue.alerts, [.error("second"), .sessionNotSaved])
    }

    func test_dismiss_removesOnlyTheAlertOnScreen_once() {
        var queue = TrackingAlertQueue()
        queue.enqueue(.error("first"))
        queue.enqueue(.sessionNotSaved)

        XCTAssertFalse(queue.dismiss(.sessionNotSaved), "the warning is not on screen yet")
        XCTAssertTrue(queue.dismiss(.error("first")))
        XCTAssertFalse(queue.dismiss(.error("first")), "a second call for the same OK removes nothing")

        XCTAssertEqual(queue.alerts, [.sessionNotSaved])
    }
}
