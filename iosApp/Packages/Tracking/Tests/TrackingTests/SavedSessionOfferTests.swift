//
//  SavedSessionOfferTests.swift
//  TrackingTests
//
//  The offer decision for each restored state, and the model that restores once per launch.
//

import SharedKit
import TestSupport
@testable import Tracking
import XCTest

@MainActor
final class SavedSessionOfferTests: TrackingTestCase {

    private let twoPoints = Array(TrackingFixtures.movingPath.prefix(2))

    // MARK: - Decision

    func test_offer_idle_isNil() {
        XCTAssertNil(savedSessionOffer(for: TrackingStateIdle.shared, activityType: .cycling))
    }

    func test_offer_tracking_isNeverOffered() {
        let tracking = TrackingStateTracking(metrics: TrackingFixtures.metrics(path: twoPoints))
        XCTAssertNil(savedSessionOffer(for: tracking, activityType: .cycling))
    }

    func test_offer_pausedWithPath_isTheTrackingRouteFromTheFirstPoint() {
        let paused = TrackingStatePaused(metrics: TrackingFixtures.metrics(path: TrackingFixtures.movingPath))

        let offer = savedSessionOffer(for: paused, activityType: .cycling)

        XCTAssertEqual(offer?.startPoint, TrackingFixtures.startPoint)
        XCTAssertEqual(offer?.plannedRoutePoints, [])
        XCTAssertEqual(offer?.selectedActivityType, .cycling)
    }

    func test_offer_pausedWithoutPath_isNil() {
        let paused = TrackingStatePaused(metrics: TrackingFixtures.metrics(path: []))
        XCTAssertNil(savedSessionOffer(for: paused, activityType: .cycling))
    }

    func test_offer_finishedWithPath_isOffered() {
        let finished = TrackingStateFinished(metrics: TrackingFixtures.metrics(path: twoPoints))
        XCTAssertNotNil(savedSessionOffer(for: finished, activityType: .walking))
    }

    func test_offer_finishedWithoutPath_isNil() {
        let finished = TrackingStateFinished(metrics: TrackingFixtures.metrics(path: []))
        XCTAssertNil(savedSessionOffer(for: finished, activityType: .walking))
    }

    func test_offer_sessionStoredWithoutType_usesTheRouteScreensDefault() {
        let paused = TrackingStatePaused(metrics: TrackingFixtures.metrics(path: twoPoints))
        XCTAssertEqual(savedSessionOffer(for: paused, activityType: nil)?.selectedActivityType, .running)
    }

    // MARK: - Model

    func test_restoreOnce_withStoredPausedSession_publishesTheOffer() async {
        let paused = TrackingStatePaused(metrics: TrackingFixtures.metrics(path: TrackingFixtures.movingPath))
        let subject = makeSubject(sessionStore: FakeTrackingSessionStore(
            stored: TrackingFixtures.storedSession(paused, activityType: .walking)
        ))
        let model = SavedSessionOfferModel(trackingSessionManager: subject.trackingSessionManager)

        await model.restoreOnce()

        XCTAssertEqual(model.offer?.startPoint, TrackingFixtures.startPoint)
        XCTAssertEqual(model.offer?.selectedActivityType, .walking)
        XCTAssertFalse(model.restoreFailed)
        model.offerConsumed()
        XCTAssertNil(model.offer)
    }

    func test_restoreOnce_withNothingStored_offersNothing() async {
        let subject = makeSubject()
        let model = SavedSessionOfferModel(trackingSessionManager: subject.trackingSessionManager)

        await model.restoreOnce()

        XCTAssertNil(model.offer)
        XCTAssertFalse(model.restoreFailed)
    }

    func test_restoreOnce_whenTheStoreFails_offersNothingAndKeepsTheSessionStored() async {
        let paused = TrackingStatePaused(metrics: TrackingFixtures.metrics(path: TrackingFixtures.movingPath))
        let store = FakeTrackingSessionStore(stored: TrackingFixtures.storedSession(paused))
        store.setLoadFailing(true)
        let subject = makeSubject(sessionStore: store)
        let model = SavedSessionOfferModel(trackingSessionManager: subject.trackingSessionManager)

        await model.restoreOnce()

        XCTAssertNil(model.offer)
        XCTAssertTrue(model.restoreFailed)
        XCTAssertNotNil(store.storedSession)
        XCTAssertEqual(store.clearCount, 0)
        model.restoreFailureAcknowledged()
        XCTAssertFalse(model.restoreFailed)
    }

    func test_restoreOnce_calledTwice_readsTheStoreOnce() async {
        let paused = TrackingStatePaused(metrics: TrackingFixtures.metrics(path: TrackingFixtures.movingPath))
        let store = FakeTrackingSessionStore(stored: TrackingFixtures.storedSession(paused))
        let subject = makeSubject(sessionStore: store)
        let model = SavedSessionOfferModel(trackingSessionManager: subject.trackingSessionManager)

        await model.restoreOnce()
        model.offerConsumed()
        await model.restoreOnce()

        XCTAssertEqual(store.loadCount, 1)
        XCTAssertNil(model.offer, "A consumed offer is not offered a second time")
    }

    func test_restoreOnce_endsOrphanedLiveActivitiesBeforeTheOfferIsPublished() async {
        let paused = TrackingStatePaused(metrics: TrackingFixtures.metrics(path: TrackingFixtures.movingPath))
        let subject = makeSubject(sessionStore: FakeTrackingSessionStore(stored: TrackingFixtures.storedSession(paused)))
        var offerWhenEnded: AppRouteTracking?
        var endCount = 0
        var model: SavedSessionOfferModel?
        model = SavedSessionOfferModel(trackingSessionManager: subject.trackingSessionManager) {
            endCount += 1
            offerWhenEnded = model?.offer
        }

        await model?.restoreOnce()
        await model?.restoreOnce()

        XCTAssertEqual(endCount, 1, "Once per launch")
        XCTAssertNil(offerWhenEnded, "The orphans are gone before the offer exists")
        XCTAssertNotNil(model?.offer)
    }
}
