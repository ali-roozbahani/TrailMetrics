package dev.roozbahani.trailmetrics.core.testing

import dev.roozbahani.trailmetrics.domain.util.SnapshotFileDeleter
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Records every path it was asked to delete. With [deleteFromDisk] it also removes the file, for
 * tests that assert on the files left behind; the default only records.
 */
class FakeSnapshotFileDeleter(
    private val deleteFromDisk: Boolean = false
) : SnapshotFileDeleter {

    /** Every call's path in order, recorded before the gate. */
    val requestedPaths = mutableListOf<String?>()

    /** The paths whose call ran to its end (after the gate and the failure check). */
    val completedPaths = mutableListOf<String?>()

    /** When set, [delete] suspends until it is completed. */
    var gate: CompletableDeferred<Unit>? = null

    /**
     * When set, [delete] throws it after the gate. The real deleter never throws; this is for
     * callers' resilience tests.
     */
    var failure: Throwable? = null

    override fun resolve(storedPath: String?): String? = storedPath?.takeIf { it.isNotBlank() }

    override suspend fun delete(storedPath: String?) {
        requestedPaths += storedPath
        // Like the real deleter, the wait is not cancellable: a caller being cleared still completes it.
        gate?.let { held -> withContext(NonCancellable) { held.await() } }
        failure?.let { throw it }
        if (deleteFromDisk && !storedPath.isNullOrBlank()) File(storedPath).delete()
        completedPaths += storedPath
    }
}
