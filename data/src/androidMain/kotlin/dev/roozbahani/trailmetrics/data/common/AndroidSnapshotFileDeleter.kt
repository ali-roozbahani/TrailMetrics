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
        withContext(NonCancellable + ioDispatcher) {
            try {
                File(storedPath).delete()
            } catch (_: SecurityException) {
                // Best effort: a file this process may not remove stays where it is.
            }
        }
    }
}
