//
//  TrackingMapPlanTests.swift
//  TrackingTests
//
//  Which recorded points the map draws and what the camera does (the map itself is not tested).
//

import SharedKit
@testable import Tracking
import XCTest

final class TrackingMapPlanTests: XCTestCase {

    private let points = TrackingFixtures.movingPath

    // MARK: - Points to draw

    func test_recordedPathToDraw_withNoPoint_drawsNothing() {
        XCTAssertEqual(recordedPathToDraw([]), [])
    }

    func test_recordedPathToDraw_withOnePoint_drawsNothing() {
        XCTAssertEqual(recordedPathToDraw([points[0]]), [])
    }

    func test_recordedPathToDraw_withTwoPoints_drawsThem() {
        XCTAssertEqual(recordedPathToDraw(Array(points.prefix(2))), Array(points.prefix(2)))
    }

    func test_recordedPathToDraw_withManyPoints_drawsAllOfThem() {
        XCTAssertEqual(recordedPathToDraw(points), points)
    }

    // MARK: - Traveled segment

    func test_traveledSegmentToDraw_withNoRecordedPoint_drawsTheSegment() {
        XCTAssertEqual(traveledSegmentToDraw(points, recordedPath: []), points)
    }

    func test_traveledSegmentToDraw_withOneRecordedPoint_drawsTheSegment() {
        XCTAssertEqual(traveledSegmentToDraw(points, recordedPath: [points[0]]), points)
    }

    func test_traveledSegmentToDraw_withTwoRecordedPoints_drawsNothing() {
        XCTAssertEqual(traveledSegmentToDraw(points, recordedPath: Array(points.prefix(2))), [])
    }

    func test_traveledSegmentToDraw_withoutASegment_drawsNothing() {
        XCTAssertEqual(traveledSegmentToDraw([], recordedPath: []), [])
        XCTAssertEqual(traveledSegmentToDraw([], recordedPath: points), [])
    }

    // MARK: - Camera

    func test_cameraPlan_withNoPoint_doesNothing() {
        XCTAssertEqual(cameraPlan(for: [], pathAlreadySeen: false), .none)
        XCTAssertEqual(cameraPlan(for: [], pathAlreadySeen: true), .none)
    }

    func test_cameraPlan_restoredPathAsTheFirstPath_fitsOnce() {
        XCTAssertEqual(cameraPlan(for: points, pathAlreadySeen: false), .fitPath)
        XCTAssertEqual(cameraPlan(for: points, pathAlreadySeen: true), .followLastPoint)
    }

    func test_cameraPlan_liveSessionStartingWithOnePoint_followsTheLastPoint() {
        XCTAssertEqual(cameraPlan(for: [points[0]], pathAlreadySeen: false), .followLastPoint)
    }

    func test_cameraPlan_everyLaterChangeOfALiveSession_followsTheLastPoint() {
        XCTAssertEqual(cameraPlan(for: Array(points.prefix(2)), pathAlreadySeen: true), .followLastPoint)
        XCTAssertEqual(cameraPlan(for: points, pathAlreadySeen: true), .followLastPoint)
    }
}
