package dev.roozbahani.trailmetrics.data.common

import dev.roozbahani.trailmetrics.domain.util.SnapshotFileDeleter
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Deletes the stored snapshot file (a regular file only) on [ioDispatcher]. The delete is not cancellable: a caller that
 * is being cleared (a ViewModel's `onCleared` runs after its scope is cancelled) still gets the file
 * removed, and the work is one short file operation.
 */
class AndroidSnapshotFileDeleter(
    private val ioDispatcher: CoroutineDispatcher
) : SnapshotFileDeleter {

    // The stored path is used as it is: the files directory of an Android app keeps its path.
    override fun resolve(storedPath: String?): String? = storedPath?.takeIf { it.isNotBlank() }

    override suspend fun delete(storedPath: String?) {
        val path = resolve(storedPath) ?: return
        withContext(NonCancellable + ioDispatcher) {
            val file = File(path)
            // Only a regular file: a path that names a directory deletes nothing. Best effort:
            // `delete()` returns false for a file that cannot be removed.
            if (file.isFile) file.delete()
        }
    }
}
