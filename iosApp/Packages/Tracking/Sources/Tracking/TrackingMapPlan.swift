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
