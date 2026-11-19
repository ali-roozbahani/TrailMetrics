//
//  TrackingLiveActivityControllerTests.swift
//  TrackingTests
//
//  Which Live Activities the controller ends and requests, on a fake ActivityKit. ActivityKit itself
//  (`ActivityKitLiveActivityClient`) is not covered by a test: the PR lists a human check for it.
//

import TestSupport
@testable import Tracking
import XCTest

@MainActor
final class TrackingLiveActivityControllerTests: XCTestCase {

    private let origin = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private var clockNow = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func makeController(_ client: FakeLiveActivityClient) -> TrackingLiveActivityController {
        TrackingLiveActivityController(
            client: client,
            now: { [weak self] in self?.clockNow ?? .distantPast },
            onStopRequested: {}
        )
    }

    func test_start_withNoOtherActivity_requestsOne() {
        let client = FakeLiveActivityClient()

        makeController(client).start(activityType: "Running")

        XCTAssertEqual(client.requestedTypes, ["Running"])
        XCTAssertEqual(client.endCalls, [])
    }

    func test_start_afterARestore_endsTheOrphanImmediatelyAndKeepsTheNewActivity() async {
        let client = FakeLiveActivityClient(existingIDs: ["orphan"])

        makeController(client).start(activityType: "Running")
        await waitUntil { client.endCalls.count == 1 }

        XCTAssertEqual(client.endCalls, [.init(id: "orphan", finalState: nil, dismissal: .immediate)])
        XCTAssertEqual(client.existingIDs, ["new-1"])
    }

    func test_start_whileItsOwnActivityLives_doesNothing() {
        let client = FakeLiveActivityClient()
        let controller = makeController(client)
        controller.start(activityType: "Running")

        controller.start(activityType: "Running")

        XCTAssertEqual(client.requestedTypes, ["Running"])
        XCTAssertEqual(client.endCalls, [])
    }

    func test_start_whenTheUserDismissedItsActivity_requestsANewOne() {
        let client = FakeLiveActivityClient()
        let controller = makeController(client)
        controller.start(activityType: "Running")
        client.dropAll()

        controller.start(activityType: "Running")

        XCTAssertEqual(client.requestedTypes, ["Running", "Running"])
    }

    func test_start_withActivitiesDisabled_doesNothing() {
        let client = FakeLiveActivityClient(existingIDs: ["orphan"])
        client.areActivitiesEnabled = false

        makeController(client).start(activityType: "Running")

        XCTAssertEqual(client.requestedTypes, [])
        XCTAssertEqual(client.endCalls, [])
    }

    func test_end_endsItsOwnWithTheFinalTotalsAndEveryOtherImmediately() async {
        let client = FakeLiveActivityClient()
        let controller = makeController(client)
        controller.start(activityType: "Running")
        client.addExisting("late-orphan")

        controller.end(distanceMeters: 120, elapsedMillis: 5_000, currentSpeedMetersPerSecond: nil)
        await waitUntil { client.endCalls.count == 2 }

        let finalState = TrackingActivityAttributes.ContentState(
            distanceMeters: 120,
            currentSpeedMetersPerSecond: nil,
            timerStart: origin.addingTimeInterval(-5),
            pausedAt: origin
        )
        XCTAssertEqual(client.endCalls, [
            .init(id: "new-1", finalState: finalState, dismissal: .afterDelay(5)),
            .init(id: "late-orphan", finalState: nil, dismissal: .immediate)
        ])
        XCTAssertEqual(client.existingIDs, [])
    }

    func test_end_withoutAnOwnActivity_stillEndsTheOrphans() async {
        let client = FakeLiveActivityClient(existingIDs: ["orphan"])

        makeController(client).end(distanceMeters: 0, elapsedMillis: 0, currentSpeedMetersPerSecond: nil)
        await waitUntil { client.endCalls.count == 1 }

        XCTAssertEqual(client.endCalls, [.init(id: "orphan", finalState: nil, dismissal: .immediate)])
    }

    func test_update_isSentToItsOwnActivityOnlyAndThrottled() async {
        let client = FakeLiveActivityClient(existingIDs: ["orphan"])
        let controller = makeController(client)
        controller.update(distanceMeters: 1, elapsedMillis: 1, currentSpeedMetersPerSecond: nil, isPaused: false)
        XCTAssertEqual(client.updatedIDs, [], "Nothing to update before start")
        controller.start(activityType: "Running")

        controller.update(distanceMeters: 1, elapsedMillis: 1, currentSpeedMetersPerSecond: nil, isPaused: false)
        controller.update(distanceMeters: 2, elapsedMillis: 2, currentSpeedMetersPerSecond: nil, isPaused: false)
        await waitUntil { !client.updatedIDs.isEmpty }

        XCTAssertEqual(client.updatedIDs, ["new-1"], "The second update falls inside the 1 s throttle")
    }

    func test_endOrphanedLiveActivities_endsEveryExistingActivityImmediately() async {
        let client = FakeLiveActivityClient(existingIDs: ["a", "b"])

        await endOrphanedLiveActivities(client: client)

        XCTAssertEqual(client.endCalls.map(\.id), ["a", "b"])
        XCTAssertTrue(client.endCalls.allSatisfy { $0.dismissal == .immediate && $0.finalState == nil })
        XCTAssertEqual(client.existingIDs, [])
    }

    // MARK: - The timer is drawn by the system from a start date; Paused holds it; stale marks old data

    private func startedController(_ client: FakeLiveActivityClient) -> TrackingLiveActivityController {
        let controller = makeController(client)
        controller.start(activityType: "Running")
        return controller
    }

    func test_start_requestsARunningTimerAtZeroWithNoStaleDateYet() {
        let client = FakeLiveActivityClient()

        _ = startedController(client)

        XCTAssertEqual(client.requested, [
            .init(
                state: .init(distanceMeters: 0, currentSpeedMetersPerSecond: nil, timerStart: origin, pausedAt: nil),
                staleDate: origin.addingTimeInterval(TrackingLiveActivityController.staleInterval)
            )
        ])
    }

    func test_update_whileRunning_anchorsTheTimerToNowMinusElapsedAndSetsAStaleDate() async {
        let client = FakeLiveActivityClient()
        let controller = startedController(client)
        clockNow = origin.addingTimeInterval(10)

        controller.update(distanceMeters: 30, elapsedMillis: 7_000, currentSpeedMetersPerSecond: 3, isPaused: false)
        await waitUntil { client.updates.count == 1 }

        XCTAssertEqual(client.updates, [
            .init(
                state: .init(
                    distanceMeters: 30,
                    currentSpeedMetersPerSecond: 3,
                    timerStart: origin.addingTimeInterval(3),
                    pausedAt: nil
                ),
                staleDate: origin.addingTimeInterval(10 + TrackingLiveActivityController.staleInterval)
            )
        ])
    }

    func test_update_whilePaused_holdsTheTimerAtNowAndHasNoStaleDate() async {
        let client = FakeLiveActivityClient()
        let controller = startedController(client)
        clockNow = origin.addingTimeInterval(10)

        controller.update(distanceMeters: 30, elapsedMillis: 7_000, currentSpeedMetersPerSecond: nil, isPaused: true)
        await waitUntil { client.updates.count == 1 }

        XCTAssertEqual(client.updates, [
            .init(
                state: .init(
                    distanceMeters: 30,
                    currentSpeedMetersPerSecond: nil,
                    timerStart: origin.addingTimeInterval(3),
                    pausedAt: origin.addingTimeInterval(10)
                ),
                staleDate: nil
            )
        ])
    }

    func test_update_pauseRightAfterARunningUpdate_isNotThrottled() async {
        let client = FakeLiveActivityClient()
        let controller = startedController(client)
        controller.update(distanceMeters: 1, elapsedMillis: 1_000, currentSpeedMetersPerSecond: nil, isPaused: false)
        clockNow = origin.addingTimeInterval(0.2)

        controller.update(distanceMeters: 1, elapsedMillis: 1_200, currentSpeedMetersPerSecond: nil, isPaused: true)
        await waitUntil { client.updates.count == 2 }

        XCTAssertEqual(client.updates.map(\.state.pausedAt), [nil, origin.addingTimeInterval(0.2)])
    }

    func test_end_freezesTheTimerAtTheEndOfTheSession() async {
        let client = FakeLiveActivityClient()
        let controller = startedController(client)
        clockNow = origin.addingTimeInterval(20)

        controller.end(distanceMeters: 50, elapsedMillis: 9_000, currentSpeedMetersPerSecond: nil)
        await waitUntil { client.endCalls.count == 1 }

        XCTAssertEqual(
            client.endCalls.first?.finalState,
            .init(
                distanceMeters: 50,
                currentSpeedMetersPerSecond: nil,
                timerStart: origin.addingTimeInterval(11),
                pausedAt: origin.addingTimeInterval(20)
            )
        )
    }
}
