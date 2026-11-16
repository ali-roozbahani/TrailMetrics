//
//  TrackingMapChangesTests.swift
//  TrackingTests
//
//  What the tracking map redraws when its content changes: only what differs, never the whole map.
//

@testable import Tracking
import SharedKit
import XCTest

final class TrackingMapChangesTests: XCTestCase {

    private let planned = TrackingFixtures.plannedRoutePoints
    private let walked = TrackingFixtures.movingPath
    private let start = TrackingFixtures.startPoint

    private func content(
        planned: [Coordinates]? = nil,
        traveled: [Coordinates] = [],
        recorded: [Coordinates] = [],
        marker: Coordinates? = nil
    ) -> TrackingMapContent {
        TrackingMapContent(
            plannedRoutePoints: planned ?? self.planned,
            traveledSegment: traveled,
            recordedPath: recorded,
            marker: marker ?? start
        )
    }

    func test_firstContent_drawsWhatThereIsAndPlacesTheMarker() {
        let changes = trackingMapChanges(from: nil, to: content(recorded: walked))

        XCTAssertEqual(changes, TrackingMapChanges(
            redrawsPlannedRoute: true,
            redrawsTraveledSegment: false,
            redrawsRecordedLine: true,
            movesMarker: true
        ))
    }

    func test_sameContent_changesNothing() {
        let shown = content(recorded: walked)

        let changes = trackingMapChanges(from: shown, to: shown)

        XCTAssertTrue(changes.isEmpty, "Nothing changed, nothing is redrawn: \(changes)")
    }

    func test_oneMoreRecordedPoint_redrawsOnlyTheRecordedLineAndMovesTheMarker() {
        let before = content(recorded: Array(walked.prefix(2)), marker: walked[1])
        let after = content(recorded: walked, marker: walked[2])

        let changes = trackingMapChanges(from: before, to: after)

        XCTAssertEqual(changes, TrackingMapChanges(
            redrawsPlannedRoute: false,
            redrawsTraveledSegment: false,
            redrawsRecordedLine: true,
            movesMarker: true
        ))
    }

    func test_locationMovesWithTheSamePath_onlyMovesTheMarker() {
        let before = content(recorded: walked, marker: walked[1])
        let after = content(recorded: walked, marker: walked[2])

        let changes = trackingMapChanges(from: before, to: after)

        XCTAssertEqual(changes, TrackingMapChanges(
            redrawsPlannedRoute: false,
            redrawsTraveledSegment: false,
            redrawsRecordedLine: false,
            movesMarker: true
        ))
    }

    func test_theRecordedLineStartsWhileTheTraveledSegmentWasShown_replacesBoth() {
        let traveled = Array(planned.prefix(2))
        let before = content(traveled: traveled, recorded: [start])
        let after = content(traveled: traveled, recorded: Array(walked.prefix(2)))

        let changes = trackingMapChanges(from: before, to: after)

        XCTAssertTrue(changes.redrawsTraveledSegment, "The segment is dropped once the recorded line is drawn")
        XCTAssertTrue(changes.redrawsRecordedLine)
        XCTAssertFalse(changes.redrawsPlannedRoute)
    }

    func test_aPlannedRouteThatArrivesLater_redrawsOnlyThePlannedRoute() {
        let before = content(planned: [], recorded: walked)
        let after = content(planned: planned, recorded: walked)

        let changes = trackingMapChanges(from: before, to: after)

        XCTAssertEqual(changes, TrackingMapChanges(
            redrawsPlannedRoute: true,
            redrawsTraveledSegment: false,
            redrawsRecordedLine: false,
            movesMarker: false
        ))
    }
}
