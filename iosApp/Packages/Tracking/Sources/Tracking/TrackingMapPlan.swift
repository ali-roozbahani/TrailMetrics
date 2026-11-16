//
//  TrackingMapPlan.swift
//  Tracking
//
//  The map decisions that need no map: which recorded points are drawn and what the camera does.
//  The same rules as Android's `recordedPathToDraw` and `cameraPlanFor` (TrackingViewModel.kt).
//

import SharedKit

/// A line needs two points, so a shorter recorded path draws nothing.
private let minimumPointsForLine = 2

func recordedPathToDraw(_ path: [Coordinates]) -> [Coordinates] {
    path.count >= minimumPointsForLine ? path : []
}

/// The traveled segment of the planned route is drawn only while the recorded path is not (fewer than two
/// points). Once it is, the recorded line alone shows the way travelled and the planned route stays gray
/// under it: drawing both gave a doubled ring, as the two lines differ a little.
func traveledSegmentToDraw(_ traveledSegment: [Coordinates], recordedPath: [Coordinates]) -> [Coordinates] {
    recordedPathToDraw(recordedPath).isEmpty ? traveledSegment : []
}

/// What the camera does when the recorded path changes.
enum CameraPlan: Equatable {
    case none
    case fitPath
    case followLastPoint
}

/// Decides the camera for `path`. `pathAlreadySeen` is true once a non-empty path has been handled.
/// A restored session arrives with a path of two or more points as its first non-empty path: fit it once.
/// A live session starts with one point, so it is never fitted and follows the last point, as does every
/// later change.
func cameraPlan(for path: [Coordinates], pathAlreadySeen: Bool) -> CameraPlan {
    if path.isEmpty { return .none }
    if !pathAlreadySeen && path.count >= minimumPointsForLine { return .fitPath }
    return .followLastPoint
}

/// What the tracking map shows: the three lines as drawn (a line shorter than two points is empty) and the
/// current location marker.
struct TrackingMapContent: Equatable {
    var plannedRoute: [Coordinates]
    var traveledSegment: [Coordinates]
    var recordedLine: [Coordinates]
    var marker: Coordinates

    init(
        plannedRoutePoints: [Coordinates],
        traveledSegment: [Coordinates],
        recordedPath: [Coordinates],
        marker: Coordinates
    ) {
        self.plannedRoute = plannedRoutePoints
        self.traveledSegment = traveledSegmentToDraw(traveledSegment, recordedPath: recordedPath)
        self.recordedLine = recordedPathToDraw(recordedPath)
        self.marker = marker
    }
}

/// What the map has to change to go from the content it shows to the new one: a line whose points differ is
/// redrawn (or removed when it is empty now), the marker moves when the location differs.
struct TrackingMapChanges: Equatable {
    var redrawsPlannedRoute: Bool
    var redrawsTraveledSegment: Bool
    var redrawsRecordedLine: Bool
    var movesMarker: Bool

    var isEmpty: Bool {
        !redrawsPlannedRoute && !redrawsTraveledSegment && !redrawsRecordedLine && !movesMarker
    }
}

/// `old` is nil before the map shows anything. The map is never cleared as a whole: only what differs.
func trackingMapChanges(from old: TrackingMapContent?, to new: TrackingMapContent) -> TrackingMapChanges {
    TrackingMapChanges(
        redrawsPlannedRoute: (old?.plannedRoute ?? []) != new.plannedRoute,
        redrawsTraveledSegment: (old?.traveledSegment ?? []) != new.traveledSegment,
        redrawsRecordedLine: (old?.recordedLine ?? []) != new.recordedLine,
        movesMarker: old?.marker != new.marker
    )
}

/// The drawing order of the map's overlays, lowest first (`zIndex`). The lines are no longer all created in
/// one fixed order on every update, so the order is stated: a planned route that arrives after the recorded
/// line (a restored session) must not be drawn over it, and the position dot stays on top of every line.
enum TrackingMapLayer {
    static let plannedRoute: Int32 = 0
    static let traveledSegment: Int32 = 1
    static let recordedLine: Int32 = 2
    static let positionMarker: Int32 = 3
}
