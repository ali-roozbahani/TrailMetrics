package dev.roozbahani.trailmetrics.domain.util

import kotlin.coroutines.cancellation.CancellationException

/**
 * Deletes the map snapshot image that an activity (or a Finish that did not save) references.
 *
 * Best effort: the callers run it only after the record is gone or when the file is an orphan, so a
 * file that is blank, missing or cannot be removed is not an error and is never thrown. The
 * implementation runs the file access off the main thread, so a caller may call it from any
 * dispatcher.
 */
interface SnapshotFileDeleter {
    /** [storedPath] is the path as stored on the activity; null or blank means there is no file. */
    @Throws(CancellationException::class)
    suspend fun delete(storedPath: String?)
}
