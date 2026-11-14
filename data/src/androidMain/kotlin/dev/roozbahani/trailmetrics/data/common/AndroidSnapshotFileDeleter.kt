package dev.roozbahani.trailmetrics.data.common

import dev.roozbahani.trailmetrics.domain.util.SnapshotFileDeleter
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Deletes the stored snapshot file on [ioDispatcher]. The delete is not cancellable: a caller that
 * is being cleared (a ViewModel's `onCleared` runs after its scope is cancelled) still gets the file
 * removed, and the work is one short file operation.
 */
class AndroidSnapshotFileDeleter(
    private val ioDispatcher: CoroutineDispatcher
) : SnapshotFileDeleter {

    override suspend fun delete(storedPath: String?) {
        if (storedPath.isNullOrBlank()) return
        // Best effort: `delete()` returns false for a file that is missing or cannot be removed.
        withContext(NonCancellable + ioDispatcher) { File(storedPath).delete() }
    }
}
