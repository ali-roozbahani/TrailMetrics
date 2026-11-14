//
//  SnapshotFileDeleting.swift
//  History
//

import Foundation

/// Deletes the map snapshot image that an activity references. The name is not
/// `SnapshotFileDeleter` because the Kotlin interface of that name is exported through `SharedKit`.
///
/// Best effort: a nil, empty, missing or undeletable path is not an error and never throws. An
/// implementation does its file access off the main actor, so a `@MainActor` caller can `await` it.
public protocol SnapshotFileDeleting: Sendable {
    func delete(storedPath: String?) async
}
